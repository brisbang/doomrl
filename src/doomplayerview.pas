{$INCLUDE doomrl.inc}
unit doomplayerview;
interface
uses viotypes, vgenerics, doomio, dfitem, dfdata, doomtrait;

type TPlayerViewState = (
  PLAYERVIEW_INVENTORY,
  PLAYERVIEW_EQUIPMENT,
  PLAYERVIEW_CHARACTER,
  PLAYERVIEW_TRAITS,
  PLAYERVIEW_CLOSING,
  PLAYERVIEW_DONE
);

type TItemViewEntry = record
  Name  : Ansistring;
  Desc  : Ansistring;
  Stats : Ansistring;
  Item  : TItem;
  Color : Byte;
end;

type TItemViewArray = specialize TGArray< TItemViewEntry >;

type TTraitViewEntry = record
  Entry     : Ansistring;
  Name      : Ansistring;
  Quote     : Ansistring;
  Desc      : Ansistring;
  Requires  : Ansistring;
  Blocks    : Ansistring;
  Available : Boolean;
  Value     : Byte;
  Index     : Byte;
end;

type TTraitViewArray = specialize TGArray< TTraitViewEntry >;
     TOnPickTrait    = function ( aTrait : Byte ) : Boolean of object;

type TPlayerView = class( TInterfaceLayer )
  constructor Create( aInitialState : TPlayerViewState = PLAYERVIEW_INVENTORY );
  constructor CreateTrait( aFirstTrait : Boolean; aKlass : Byte = 0; aCallback : TOnPickTrait = nil );
  procedure Update( aDTime : Integer ); override;
  function IsFinished : Boolean; override;
  function IsModal : Boolean; override;
  destructor Destroy; override;
protected
  procedure UpdateInventory;
  procedure UpdateEquipment;
  procedure UpdateCharacter;
  procedure UpdateTraits;
  procedure PushItem( aItem : TItem; aArray : TItemViewArray );
  procedure ReadInv;
  procedure ReadEq;
  procedure ReadTraits( aKlass : Byte );
  procedure Sort( aList : TItemViewArray );
protected
  procedure Filter( aSet : TItemTypeSet );
protected
  FState     : TPlayerViewState;
  FSize      : TIOPoint;
  FInv       : TItemViewArray;
  FEq        : TItemViewArray;
  FSwapMode  : Boolean;
  FTraitMode : Boolean;
  FTraitFirst: Boolean;
  FSSlot     : TEqSlot;
  FTraits    : TTraitViewArray;
  FOnPick    : TOnPickTrait;
end;

implementation

uses sysutils, variants,
     vutil, vtig, vtigio, vgltypes, vluasystem,
     dfplayer,
     doomcommand, doombase, doominventory, doomgfxio;

constructor TPlayerView.Create( aInitialState : TPlayerViewState = PLAYERVIEW_INVENTORY );
begin
  VTIG_EventClear;
  VTIG_ResetSelect( 'inventory' );
  VTIG_ResetSelect( 'equipment' );
  VTIG_ResetSelect( 'traits' );
  FState     := aInitialState;
  FSize      := Point( 80, 25 );
  FInv       := nil;
  FEq        := nil;
  FTraits    := nil;
  FSwapMode  := False;
  FTraitMode := False;
  FTraitFirst:= False;
end;

constructor TPlayerView.CreateTrait( aFirstTrait : Boolean; aKlass : Byte = 0; aCallback : TOnPickTrait = nil );
begin
  VTIG_EventClear;
  VTIG_ResetSelect( 'traits' );
  FState     := PLAYERVIEW_TRAITS;
  FSize      := Point( 80, 25 );
  FInv       := nil;
  FEq        := nil;
  FTraits    := nil;
  FSwapMode  := False;
  FTraitMode := True;
  FTraitFirst:= aFirstTrait;
  FOnPick    := aCallback;

  if FTraitFirst
    then ReadTraits( aKlass )
    else ReadTraits( Player.Klass )
end;

procedure TPlayerView.Update( aDTime : Integer );
var iP1,iP2 : TPoint;
begin
  if IsFinished or (FState = PLAYERVIEW_CLOSING) then Exit;

  if ( Doom.State <> DSPlaying ) and ( not FTraitFirst ) then
  begin
    FState := PLAYERVIEW_DONE;
    Exit;
  end;

  case FState of
    PLAYERVIEW_INVENTORY : UpdateInventory;
    PLAYERVIEW_EQUIPMENT : UpdateEquipment;
    PLAYERVIEW_CHARACTER : UpdateCharacter;
    PLAYERVIEW_TRAITS    : UpdateTraits;
  end;

  if IsFinished or (FState = PLAYERVIEW_CLOSING) then Exit;

  if ( not FSwapMode ) and ( not FTraitMode ) then
  begin
    if VTIG_Event( VTIG_IE_LEFT ) then
    begin
      if FState = Low( TPlayerViewState ) then FState := PLAYERVIEW_TRAITS       else FState := Pred( FState );
    end;
    if VTIG_Event( VTIG_IE_RIGHT ) then
    begin
      if FState = PLAYERVIEW_TRAITS       then FState := Low( TPlayerViewState ) else FState := Succ( FState );
    end;
  end;

  if ( FState <> PLAYERVIEW_DONE ) and ( not FTraitMode ) then
  begin
    if VTIG_EventCancel or VTIG_Event( [ TIG_EV_INVENTORY, TIG_EV_EQUIPMENT, TIG_EV_CHARACTER, TIG_EV_TRAITS ] ) then
    begin
      FState := PLAYERVIEW_DONE;
    end;
  end;

  if ( FState <> PLAYERVIEW_DONE ) and FTraitMode and FTraitFirst then
    if VTIG_EventCancel then
    begin
      FState := PLAYERVIEW_DONE;
      FOnPick(255);
    end;

  if GraphicsVersion then
    with IO as TDoomGFXIO do
    begin
      iP1 := ConsoleCoordToDeviceCoord( PointUnit );
      iP2 := ConsoleCoordToDeviceCoord( FSize + PointUnit );
      QuadSheet.PushColoredQuad( TGLVec2i.Create( iP1.x, iP1.y ), TGLVec2i.Create( iP2.x, iP2.y ), TGLVec4f.Create( 0,0,0,0.7 ) );
    end;
end;

function TPlayerView.IsFinished : Boolean;
begin
  Exit( FState = PLAYERVIEW_DONE );
end;

function TPlayerView.IsModal : Boolean;
begin
  Exit( FState <> PLAYERVIEW_CLOSING );
end;

destructor TPlayerView.Destroy;
begin
  FreeAndNil( FEq );
  FreeAndNil( FInv );
  inherited Destroy;
end;

procedure TPlayerView.UpdateInventory;
var iEntry    : TItemViewEntry;
    iSelected : Integer;
    iCommand  : Byte;
begin
  if FInv = nil then ReadInv;
  if FSwapMode
    then VTIG_BeginWindow('Select item to wear/wield', 'inventory', FSize )
    else VTIG_BeginWindow('Inventory', 'inventory', FSize );
    VTIG_BeginGroup( 50 );
    for iEntry in FInv do
      VTIG_Selectable( iEntry.Name, True, iEntry.Color );
    iSelected := VTIG_Selected;
    if FInv.Size = 0 then
    begin
      iSelected := -1;
      if FSwapMode
        then VTIG_Text( 'No matching items, press <{!Enter}>.' )
        else VTIG_Text( '{!No items in inventory!}' );
    end;

    VTIG_EndGroup;

    VTIG_BeginGroup;
    if iSelected >= 0 then
    begin
      VTIG_Text( FInv[iSelected].Desc );
      VTIG_FreeLabel( FInv[iSelected].Stats, Point( 0, 7 ) );

      VTIG_Ruler( 20 );
      VTIG_Text( '<{!Enter}> wear/use' );
      if not FSwapMode then
        VTIG_Text( '<{!Backspace}> drop' );
    end;

    VTIG_EndGroup;
  if FSwapMode
    then VTIG_End('<{!Up,Down}> select, <{!Escape}> exit}')
    else VTIG_End('{l<{!Left,Right}> panels, <{!Up,Down}> select, <{!Escape}> exit}');

  if (iSelected >= 0) then
  begin
    if FSwapMode then
    begin
      if VTIG_EventConfirm then
      begin
        FState := PLAYERVIEW_DONE;
        Doom.HandleCommand( TCommand.Create( COMMAND_SWAP, FInv[iSelected].Item, FSSlot ) );
      end;
    end
    else
    begin
      if VTIG_Event( VTIG_IE_BACKSPACE ) then
      begin
        FState := PLAYERVIEW_DONE;
        Doom.HandleCommand( TCommand.Create( COMMAND_DROP, FInv[iSelected].Item ) );
      end
      else
      if VTIG_EventConfirm then
      begin
        iCommand := COMMAND_NONE;
        if FInv[iSelected].Item.isWearable then iCommand := COMMAND_WEAR;
        if FInv[iSelected].Item.isPack     then iCommand := COMMAND_USE;
        FState := PLAYERVIEW_DONE;
        if iCommand <> COMMAND_NONE then
          Doom.HandleCommand( TCommand.Create( iCommand, FInv[iSelected].Item ) );
      end;
    end;
  end
  else
  begin
    if VTIG_EventConfirm then
      FState := PLAYERVIEW_DONE;
  end;

end;

procedure TPlayerView.UpdateEquipment;
const ResNames : array[TResistance] of AnsiString = ('Bullet','Melee','Shrap','Acid','Fire','Plasma');
      ResIDs   : array[TResistance] of AnsiString = ('bullet','melee','shrapnel','acid','fire','plasma');
var iEntry       : TItemViewEntry;
    iSelected,iY : Integer;
    iB, iA       : Integer;
    iCount       : Integer;
    iRes         : TResistance;
    iName        : Ansistring;
  function Cursed : Boolean;
  begin
    if ( FEq[iSelected].Item <> nil ) and FEq[iSelected].Item.Flags[ IF_CURSED ] then
    begin
      FState := PLAYERVIEW_DONE;
      IO.Msg('You can''t, it''s cursed!');
      Exit( True );
    end;
    Exit( False );
  end;

begin
  if FEq = nil then ReadEq;
  VTIG_BeginWindow('Equipment', 'equipment', FSize );
    VTIG_BeginGroup( 9, True );

      VTIG_BeginGroup( 50 );
        for iEntry in FEq do
          VTIG_Selectable( iEntry.Name, iEntry.Item <> nil, iEntry.Color );
      iSelected := VTIG_Selected;
      VTIG_Text( '' );
      if ( iSelected >= 0 ) and Assigned( FEq[iSelected].Item ) then
        VTIG_Text( FEq[iSelected].Desc );
      VTIG_EndGroup;

      VTIG_BeginGroup;
      if ( iSelected >= 0 ) and Assigned( FEq[iSelected].Item ) then
        VTIG_FreeLabel( FEq[iSelected].Stats, Point(0,0) );
      VTIG_EndGroup;

    VTIG_EndGroup( True );

    iY := 9;
    iB := 0;
    iA := 0;
    VTIG_FreeLabel( 'Basic traits',    Point(0, iY) );
    VTIG_FreeLabel( 'Advanced traits', Point(20,iY) );
    VTIG_FreeLabel( 'Resistances',     Point(42,iY) );

    for iCount := 1 to MAXTRAITS do
      if Player.FTraits.Values[iCount] > 0 then
      begin
        iName := LuaSystem.Get(['traits',iCount,'name']);
        if iCount < 10 then
        begin
          Inc( iB );
          VTIG_FreeLabel( '{d'+Padded(iName,16) + '({!' + IntToStr(Player.FTraits.Values[iCount])+ '})}', Point(0, iY+iB) );
        end
        else
        begin
          Inc( iA );
          VTIG_FreeLabel( '{d'+Padded(iName,16) + '({!' + IntToStr(Player.FTraits.Values[iCount])+ '})}', Point(20, iY+iA) );
        end;
      end;

    for iRes := Low(TResistance) to High(TResistance) do
    begin
      Inc( iY );
      VTIG_FreeLabel( '{d'+Padded(ResNames[iRes],7)+'{!'+Padded(BonusStr(Player.getTotalResistance(ResIDs[iRes],TARGET_INTERNAL))+'%',5)+
           '} Torso {!'+Padded(BonusStr(Player.getTotalResistance(ResIDs[iRes],TARGET_TORSO))+'%',5)+
           '} Feet {!'+Padded(BonusStr(Player.getTotalResistance(ResIDs[iRes],TARGET_FEET))+'%',5)+'}', Point( 42, iY ) );
    end;

     VTIG_FreeLabel( '<{!Enter}> take off/wear', Point(53, 18) );
     VTIG_FreeLabel( '<{!Tab}> swap item',       Point(53, 19) );
     VTIG_FreeLabel( '<{!Backspace}> drop item', Point(53, 20) );
  VTIG_End('{l<{!Left,Right}> panels, <{!Up,Down}> select, <{!Escape}> exit}');

  if (iSelected >= 0) then
  begin
    if VTIG_EventConfirm then
    begin
      if Assigned( FEq[iSelected].Item ) then
      begin
        if ( Player.Inv.isFull ) then
        begin
          FState := PLAYERVIEW_CLOSING;
          if not Option_InvFullDrop then
          begin
            if not IO.MsgConfirm('No room in inventory! Should it be dropped?') then
            begin
              FState := PLAYERVIEW_DONE;
              Exit;
            end;
          end;
          FState := PLAYERVIEW_DONE;
          if Cursed then Exit;
          Doom.HandleCommand( TCommand.Create( COMMAND_DROP, FEq[iSelected].Item ) );
        end
        else
        begin
          FState := PLAYERVIEW_DONE;
          if Cursed then Exit;
          Doom.HandleCommand( TCommand.Create( COMMAND_TAKEOFF, nil, TEqSlot(iSelected) ) );
        end;
      end
      else
      begin
        VTIG_ResetSelect( 'inventory' );
        FState    := PLAYERVIEW_INVENTORY;
        FSwapMode := True;
        Filter( ItemEqFilters[ TEqSlot(iSelected) ] );
        FSSlot := TEqSlot(iSelected);
        Exit;
      end;
    end
    else
    if VTIG_Event( VTIG_IE_TAB ) then
    begin
      if Cursed then Exit;
      VTIG_ResetSelect( 'inventory' );
      FState    := PLAYERVIEW_INVENTORY;
      FSwapMode := True;
      Filter( ItemEqFilters[ TEqSlot(iSelected) ] );
      FSSlot := TEqSlot(iSelected);
      Exit;
    end
    else
    if VTIG_Event( VTIG_IE_BACKSPACE ) then
    begin
      if Assigned( FEq[iSelected].Item ) then
        begin
          FState := PLAYERVIEW_DONE;
          if Cursed then Exit;
          Doom.HandleCommand( TCommand.Create( COMMAND_DROP, FEq[iSelected].Item ) );
        end;
    end;
  end;
end;

procedure TPlayerView.UpdateCharacter;
begin
  VTIG_BeginWindow('Character', FSize );
  VTIG_End('{l<{!Left,Right}> panels, <{!Up,Down}> scroll, <{!Escape}> exit}');
end;

procedure TPlayerView.UpdateTraits;
var iSelected : Integer;
    iEntry    : TTraitViewEntry;
begin
  if FTraits = nil then ReadTraits( Player.Klass );
  if FTraitMode
    then VTIG_BeginWindow('Select trait to upgrade', 'traits', FSize )
    else VTIG_BeginWindow('Traits', 'traits', FSize );

  VTIG_BeginGroup( 23 );
  VTIG_MoveCursor( Point(0,-1) );
    for iEntry in FTraits do
      if iEntry.Available
        then VTIG_Selectable( iEntry.Entry, True, LightRed )
        else VTIG_Selectable( iEntry.Entry, False );
    iSelected := VTIG_Selected;
  VTIG_EndGroup;

  VTIG_BeginGroup;
  if iSelected >= 0 then
  begin
    VTIG_Text( FTraits[iSelected].Name, LightRed );
    VTIG_Ruler;
    VTIG_Text( FTraits[iSelected].Quote, Yellow );
    VTIG_Text( '' );
    VTIG_Text( FTraits[iSelected].Desc );
    VTIG_Text( '' );
    if FTraits[iSelected].Requires <> '' then
      VTIG_Text( 'Requires : {0}',[FTraits[iSelected].Requires] );
    if FTraits[iSelected].Blocks <> '' then
      VTIG_Text( 'Blocks   : {0}',[FTraits[iSelected].Blocks] );
  end;
  VTIG_EndGroup;

  if FTraitMode
    then VTIG_End('{l<{!Up,Down}> scroll, <{!Enter}> select}')
    else VTIG_End('{l<{!Left,Right}> panels, <{!Up,Down}> scroll, <{!Escape}> exit}');

  if (iSelected >= 0) and FTraitMode then
    if VTIG_EventConfirm then
    begin
      FState := PLAYERVIEW_DONE;
      if FTraitFirst
        then FOnPick( FTraits[iSelected].Index )
        else Player.FTraits.Upgrade( FTraits[iSelected].Index );
    end;
end;

procedure TPlayerView.PushItem( aItem : TItem; aArray : TItemViewArray );
var iEntry : TItemViewEntry;
    iSet   : AnsiString;
begin
  iEntry.Item  := aItem;
  iEntry.Name  := aItem.Description;
  iEntry.Stats := aItem.DescriptionBox( True );
  iEntry.Color := aItem.MenuColor;

  iEntry.Desc  := LuaSystem.Get(['items',aItem.ID,'desc']);
  if aItem.Flags[ IF_SETITEM ] then
  begin
    iSet        := LuaSystem.Get(['items',aItem.ID,'set']);
    iEntry.Desc := Format('@<%s@> (1/%d)', [
      AnsiString( LuaSystem.Get(['itemsets',iSet,'name']) ),
      Byte( LuaSystem.Get(['itemsets',iSet,'trigger']) ) ])
      + #10+ iEntry.Desc;
  end;
  aArray.Push( iEntry );
end;

procedure TPlayerView.ReadInv;
var iItem  : TItem;
begin
  if FInv = nil then FInv := TItemViewArray.Create;
  FInv.Clear;

  for iItem in Player.Inv do
    if (not Player.Inv.Equipped( iItem )) {and (iItem.IType in aFilter) }then
      PushItem( iItem, FInv );

  Sort( FInv );
end;

procedure TPlayerView.ReadEq;
var iSlot  : TEqSlot;
    iEntry : TItemViewEntry;
begin
  if FEq = nil then FEq := TItemViewArray.Create;
  FEq.Clear;

  for iSlot := Low(TEqSlot) to High(TEqSlot) do
    if Player.Inv.Slot[iSlot] <> nil
      then PushItem( Player.Inv.Slot[iSlot], FEq )
      else
        begin
          iEntry.Item  := nil;
          iEntry.Name  := SlotName( iSlot );
          iEntry.Stats := '';
          iEntry.Desc  := '';
          iEntry.Color := DarkGray;
          FEq.Push( iEntry );
        end;
end;

procedure TPlayerView.ReadTraits( aKlass : Byte );
var iEntry    : TTraitViewEntry;
    iKlass    : Byte;
    iLevel    : Byte;
    iTrait, i : byte;
    iTraits   : Variant;
    iTData    : PTraits;
    iName     : AnsiString;
    iNID      : Word;
    iValue    : Word;
    iSize     : Word;
    iCount    : Word;
    iTable  : TLuaTable;
const RG : array[Boolean] of Char = ('G','R');
      RL : array[Boolean] of Char = ('L','R');
  function Value( aTrait : Byte ) : Byte;
  begin
    if FTraitFirst then Exit(0);
    Exit( iTData^.Values[aTrait] );
  end;

begin
  if FTraits = nil then FTraits := TTraitViewArray.Create;
  FTraits.Clear;

  iKlass := aKlass;
  iLevel := 0;
  iTData := nil;
  if not FTraitFirst then
  begin
    iLevel := Player.ExpLevel;
    iTData := @(Player.FTraits);
  end;

  iTraits := LuaSystem.Get(['klasses',iKlass,'traitlist']);
  for i := VarArrayLowBound(iTraits, 1) to VarArrayHighBound(iTraits, 1) do
  begin
    iTrait := iTraits[ i ];
    iEntry.Value     := Value( iTrait );
    iEntry.Name      := LuaSystem.Get(['traits',iTrait,'name']);
    iEntry.Entry     := Padded(iEntry.Name,16) +' ({!'+IntToStr(iEntry.Value)+'})';
    with LuaSystem.GetTable(['traits',iTrait]) do
    try
      iEntry.Quote := getString('quote');
      iEntry.Desc  := getString('full');
    finally
      Free;
    end;

    iEntry.Requires := '';
    iEntry.Blocks   := '';
    with LuaSystem.GetTable(['klasses',iKlass,'trait',iTrait]) do
    try
      if GetTableSize('requires') > 0 then
      for iTable in ITables('requires') do
      begin
        iNID            := iTable.GetValue( 1 );
        iName           := LuaSystem.Get(['traits',iNID,'name']);
        iValue          := iTable.GetValue( 2 );
        iEntry.Requires += '{'+RG[Value(iNID) < iValue]+iName+'} ({!'+IntToStr(iValue)+'}), ';
      end;

      iValue := GetInteger('reqlevel',0);
      if iValue > 0
        then iEntry.Requires += '{'+RG[iLevel < iValue]+'Level }({!'+IntToStr(iValue)+'})'
        else Delete( iEntry.Requires, Length(iEntry.Requires) - 1, 2 );

      iSize   := GetTableSize('blocks');
      if iSize > 0 then
      begin
        with GetTable('blocks') do
        try
          for iCount := 1 to iSize do
          begin
            iNID          := GetValue( iCount );
            iName         := LuaSystem.Get(['traits',iNID,'name']);
            iEntry.Blocks += '{'+RL[Value(iNID) > 0]+iName+'}, ';
          end;
        finally
          Free;
        end;
        Delete( iEntry.Blocks, Length(iEntry.Blocks) - 1, 2 );
      end;
    finally
      Free;
    end;

    iEntry.Index     := iTrait;
    if FTraitFirst
      then iEntry.Available := TTraits.CanPickInitially( iTrait, iKlass )
      else iEntry.Available := iTData^.CanPick( iTrait, iLevel );
    FTraits.Push( iEntry );
  end;

end;

procedure TPlayerView.Sort( aList : TItemViewArray );
var iCount  : Integer;
    iCount2 : Integer;
    iTemp   : TItemViewEntry;
begin
  for iCount := 0 to aList.Size - 1 do
    for iCount2 := 0 to aList.Size - iCount - 2 do
      if TItem.Compare(aList[iCount2].Item,aList[iCount2+1].Item) then
      begin
        iTemp := aList[iCount2];
        aList[iCount2] := aList[iCount2+1];
        aList[iCount2+1] := iTemp;
      end;
end;

procedure TPlayerView.Filter( aSet : TItemTypeSet );
var iCount  : Integer;
    iSize   : Integer;
begin
  iSize := 0;
  for iCount := 0 to FInv.Size - 1 do
    if FInv[ iCount ].Item.IType in aSet then
    begin
      if iCount <> iSize then
        FInv[ iSize ] := FInv[ iCount ];
      Inc( iSize );
    end;
  FInv.Resize( iSize );
end;

end.


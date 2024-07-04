{$INCLUDE doomrl.inc}
unit doombase;
interface

uses vsystems, vsystem, vutil, vuid, vrltools, vluasystem, vioevent,
     dflevel, dfdata, dfhof,
     doomhooks, doomlua, doommodule, doommenuview, doomcommand;

type TDoomState = ( DSStart,      DSMenu,    DSLoading,
                    DSPlaying,    DSSaving,  DSNextLevel,
                    DSQuit,       DSFinished );

type

{ TDoom }

TDoom = class(TSystem)
       Difficulty    : Byte;
       Challenge     : AnsiString;
       SChallenge    : AnsiString;
       ArchAngel     : Boolean;
       DataLoaded    : Boolean;
       GameWon       : Boolean;
       GameType      : TDoomGameType;
       Module        : TDoomModule;
       NVersion      : TVersion;
       ModuleID      : AnsiString;
       constructor Create; override;
       procedure CreateIO;
       procedure Apply( aResult : TMenuResult );
       procedure Load;
       procedure UnLoad;
       function LoadSaveFile : Boolean;
       procedure WriteSaveFile;
       function SaveExists : Boolean;
       procedure SetupLuaConstants;
       function Action( aCommand : Byte ) : Boolean;
       function HandleActionCommand( aCommand : Byte ) : Boolean;
       function HandleMoveCommand( aCommand : Byte ) : Boolean;
       function HandleFireCommand( aAlt : Boolean; aMouse : Boolean ) : Boolean;
       function HandleUnloadCommand : Boolean;
       function HandleSwapWeaponCommand : Boolean;
       function HandleCommand( aCommand : TCommand ) : Boolean;
       procedure Run;
       destructor Destroy; override;
       procedure ModuleMainHook( Hook : AnsiString; const Params : array of Const );
       procedure CallHook( Hook : Byte; const Params : array of Const );
       function  CallHookCheck( Hook : Byte; const Params : array of Const ) : Boolean;
       procedure LoadChallenge;
       procedure SetState( NewState : TDoomState );
     private
       function HandleMouseEvent( aEvent : TIOEvent ) : Boolean;
       function HandleKeyEvent( aEvent : TIOEvent ) : Boolean;
       procedure PreAction;
       function ModuleHookTable( Hook : Byte ) : AnsiString;
       procedure LoadModule( Base : Boolean );
       procedure DoomFirst;
       procedure RunSingle;
       procedure CreatePlayer( aResult : TMenuResult );
     private
       FState           : TDoomState;
       FLevel           : TLevel;
       FCoreHooks       : TFlags;
       FChallengeHooks  : TFlags;
       FSChallengeHooks : TFlags;
       FModuleHooks     : TFlags;
     public
       property Level : TLevel read FLevel;
       property ChalHooks : TFlags read FChallengeHooks;
       property ModuleHooks : TFlags read FModuleHooks;
       property State : TDoomState read FState;
     end;

var Doom : TDoom;
var Lua : TDoomLua;


implementation

uses Classes, SysUtils,
     vdebug, viotypes,
     dfmap, dfitem, dfbeing,
     dfoutput, doomio, zstream,
     doomspritemap, // remove
     doomhelp, doomconfig, doomviews, dfplayer;


procedure TDoom.ModuleMainHook(Hook: AnsiString; const Params: array of const);
begin
  if not LuaSystem.Defined([ ModuleID, Hook ]) then Exit;
  Lua.ProtectedCall( [ ModuleID, Hook ], Params );
end;


procedure TDoom.CallHook( Hook : Byte; const Params : array of const ) ;
begin
  if (Hook in FModuleHooks) then LuaSystem.ProtectedCall([ModuleHookTable(Hook),HookNames[Hook]],Params);
  if (Challenge <> '')  and (Hook in FChallengeHooks) then LuaSystem.ProtectedCall(['chal',Challenge,HookNames[Hook]],Params);
  if (SChallenge <> '') and (Hook in FSChallengeHooks) then LuaSystem.ProtectedCall(['chal',SChallenge,HookNames[Hook]],Params);
  if (Hook in FCoreHooks) then LuaSystem.ProtectedCall(['core',HookNames[Hook]],Params);
end;

function TDoom.CallHookCheck ( Hook : Byte; const Params : array of const ) : Boolean;
begin
  if (Hook in FCoreHooks) then if not LuaSystem.ProtectedCall(['core',HookNames[Hook]],Params) then Exit( False );
  if (Challenge <> '') and (Hook in FChallengeHooks) then if not LuaSystem.ProtectedCall(['chal',Challenge,HookNames[Hook]],Params) then Exit( False );
  if (SChallenge <> '') and (Hook in FSChallengeHooks) then if not LuaSystem.ProtectedCall(['chal',SChallenge,HookNames[Hook]],Params) then Exit( False );
  if Hook in FModuleHooks then if not LuaSystem.ProtectedCall([ModuleHookTable(Hook),HookNames[Hook]],Params) then Exit( False );
  Exit( True );
end;

procedure TDoom.LoadChallenge;
begin
  FChallengeHooks := [];
  FSChallengeHooks := [];
  if Challenge <> '' then
    FChallengeHooks := LoadHooks( ['chal',Challenge] ) * GlobalHooks;
  if SChallenge <> '' then
    FSChallengeHooks := LoadHooks( ['chal',SChallenge] ) * GlobalHooks;
end;

procedure TDoom.SetState(NewState: TDoomState);
begin
  FState := NewState;
end;

function TDoom.ModuleHookTable ( Hook : Byte ) : AnsiString;
begin
  if Hook in GameTypeHooks[ GameType ] then Exit( ModuleID ) else Exit( 'DoomRL' );
end;

procedure TDoom.LoadModule( Base : Boolean );
begin
  if ModuleID <> 'DoomRL' then Lua.LoadModule( Module );
  FModuleHooks := LoadHooks( ['DoomRL'] ) * GlobalHooks;
  if GameType <> GameStandard then
  begin
    Exclude( FModuleHooks, Hook_OnLoad );
    Exclude( FModuleHooks, Hook_OnLoaded );
    Exclude( FModuleHooks, Hook_OnIntro );
    FModuleHooks += ( LoadHooks( [ ModuleID ] ) * GameTypeHooks[ GameType ] );
  end;
  if Base then CallHook( Hook_OnLoadBase, [] );
  CallHook( Hook_OnLoad, [] );
end;

procedure TDoom.Load;
begin
  FreeAndNil( Config );
  IO.LoadStart;
  ColorOverrides := TIntHashMap.Create( );
  Config := TDoomConfig.Create( ConfigurationPath, True );
  IO.Configure( Config, True );

  FCoreHooks := [];
  FModuleHooks := [];
  FChallengeHooks := [];
  FSChallengeHooks := [];
  Cells := TCells.Create;
  Help := THelp.Create;

  SetState( DSLoading );
  LuaSystem := Systems.Add(TDoomLua.Create()) as TLuaSystem;
  LuaSystem.CallDefaultResult := True;
  Modules.RegisterAwards( LuaSystem.Raw );
  FCoreHooks := LoadHooks( [ 'core' ] ) * GlobalHooks;
  ModuleID := 'DoomRL';
  UI.CreateMessageWriter( Config );
  LoadModule( True );

  if GodMode and FileExists( WritePath + 'god.lua') then
    Lua.LoadFile( WritePath + 'god.lua');
  HOF.Init;
  FLevel := TLevel.Create;
  if not GraphicsVersion then
    UI.SetTextMap( FLevel );
  DataLoaded := True;
  IO.LoadStop;
end;

procedure TDoom.UnLoad;
begin
  DataLoaded := False;
  HOF.Done;
  FreeAndNil(LuaSystem);
  FreeAndNil(Config);
  FreeAndNil(Help);
  FreeAndNil(FLevel);
  FreeAndNil(ColorOverrides);
  FreeAndNil(Cells);
end;

constructor TDoom.Create;
begin
  inherited Create;
  ModuleID   := 'DoomRL';
  GameType   := GameStandard;
  GameWon    := False;
  DataLoaded := False;
  SetState( DSStart );
  FModuleHooks := [];
  FChallengeHooks := [];
  NVersion := ArrayToVersion(VERSION_ARRAY);
  Log( VersionToString( NVersion ) );
end;

procedure TDoom.CreateIO;
begin
  IO := TDoomIO.Create;
  ProgramRealTime := MSecNow();
  IO.Configure( Config );
end;

procedure TDoom.Apply ( aResult : TMenuResult ) ;
begin
  if aResult.Quit   then SetState( DSQuit );
  if aResult.Loaded then Exit;
  Difficulty     := aResult.Difficulty;
  Challenge      := aResult.Challenge;
  ArchAngel      := aResult.ArchAngel;
  SChallenge     := aResult.SChallenge;
  GameType       := aResult.GameType;
  ModuleID       := aResult.ModuleID;

  if aResult.Module <> nil then
  begin
    NoPlayerRecord := True;
    NoScoreRecord  := True;
    Module := aResult.Module;
  end;

  // Set Klass   Klass      : Byte;
  // Upgrade trait -- Trait : Byte;
  // Set Name    Name       : AnsiString;
end;

procedure TDoom.PreAction;
begin
  FLevel.CalculateVision( Player.Position );
  StatusEffect := Player.FAffects.getEffect;
  UI.Focus( Player.Position );
  if GraphicsVersion then
    UI.UpdateMinimap;
  Player.PreAction;
end;

function TDoom.Action( aCommand : Byte ) : Boolean;
var iItem : TItem;
begin

  if aCommand in INPUT_MOVE then
    Exit( HandleMoveCommand( aCommand ) );

  case aCommand of
    INPUT_FIRE       : Exit( HandleFireCommand( False, False ) );
    INPUT_ALTFIRE    : Exit( HandleFireCommand( True, False ) );
    INPUT_ACTION     : Exit( HandleActionCommand( INPUT_ACTION ) );
    INPUT_OPEN       : Exit( HandleActionCommand( INPUT_OPEN ) );
    INPUT_CLOSE      : Exit( HandleActionCommand( INPUT_CLOSE ) );
    INPUT_UNLOAD     : Exit( HandleUnloadCommand );
    INPUT_QUICKKEY_0 : Exit( HandleCommand( TCommand.Create( COMMAND_QUICKKEY, 'chainsaw' ) ) );
    INPUT_QUICKKEY_1 : Exit( HandleCommand( TCommand.Create( COMMAND_QUICKKEY, 'knife' ) ) );
    INPUT_QUICKKEY_2 : Exit( HandleCommand( TCommand.Create( COMMAND_QUICKKEY, 'pistol' ) ) );
    INPUT_QUICKKEY_3 : Exit( HandleCommand( TCommand.Create( COMMAND_QUICKKEY, 'shotgun' ) ) );
    INPUT_QUICKKEY_4 : Exit( HandleCommand( TCommand.Create( COMMAND_QUICKKEY, 'ashotgun' ) ) );
    INPUT_QUICKKEY_5 : Exit( HandleCommand( TCommand.Create( COMMAND_QUICKKEY, 'dshotgun' ) ) );
    INPUT_QUICKKEY_6 : Exit( HandleCommand( TCommand.Create( COMMAND_QUICKKEY, 'chaingun' ) ) );
    INPUT_QUICKKEY_7 : Exit( HandleCommand( TCommand.Create( COMMAND_QUICKKEY, 'bazooka' ) ) );
    INPUT_QUICKKEY_8 : Exit( HandleCommand( TCommand.Create( COMMAND_QUICKKEY, 'plasma' ) ) );
    INPUT_QUICKKEY_9 : Exit( HandleCommand( TCommand.Create( COMMAND_QUICKKEY, 'bfg9000' ) ) );

    INPUT_TACTIC     : Exit( HandleCommand( TCommand.Create( COMMAND_TACTIC ) ) );
    INPUT_WAIT       : Exit( HandleCommand( TCommand.Create( COMMAND_WAIT ) ) );
    INPUT_RELOAD     : Exit( HandleCommand( TCommand.Create( COMMAND_RELOAD ) ) );
    INPUT_ALTRELOAD  : Exit( HandleCommand( TCommand.Create( COMMAND_ALTRELOAD ) ) );
    INPUT_PICKUP     : Exit( HandleCommand( TCommand.Create( COMMAND_PICKUP ) ) );
    INPUT_ENTER      : Exit( HandleCommand( TCommand.Create( COMMAND_ENTER ) ) );

    INPUT_USE        : begin
      iItem := Player.Inv.Choose([ITEMTYPE_PACK],'use');
      if iItem = nil then Exit( False );
      Exit( HandleCommand( TCommand.Create( COMMAND_USE, iItem ) ) );
    end;
    INPUT_DROP       : begin
      iItem := Player.Inv.Choose([],'drop');
      if iItem = nil then Exit( False );
      Exit( HandleCommand( TCommand.Create( COMMAND_DROP, iItem ) ) );
    end;

    INPUT_ALTPICKUP  : begin
      iItem := Level.Item[ Player.Position ];
      if ( iItem = nil ) or (not (iItem.isLever or iItem.isPack or iItem.isWearable) ) then
      begin
        UI.Msg( 'There''s nothing to use on the ground!' );
        Exit( False );
      end;
      Exit( HandleCommand( TCommand.Create( COMMAND_USE, iItem ) ) );
    end;

    INPUT_INVENTORY   : Exit( HandleCommand( Player.Inv.View ) );
    INPUT_EQUIPMENT   : Exit( HandleCommand( Player.Inv.RunEq ) );
    INPUT_MSCROLL     : Exit( HandleCommand( Player.Inv.DoScrollSwap ) );

    INPUT_SWAPWEAPON  : Exit( HandleSwapWeaponCommand );
  end;

  UI.Msg('Unknown command. Press "?" for help.' );
  Exit( False );
end;

function TDoom.HandleActionCommand( aCommand : Byte ) : Boolean;
var iItem   : TItem;
    iID     : AnsiString;
    iFlag   : Byte;
    iCount  : Byte;
    iScan   : TCoord2D;
    iTarget : TCoord2D;
    iDir    : TDirection;
begin
  iFlag := 0;

  if aCommand = INPUT_ACTION then
  begin
    if Level.cellFlagSet( Player.Position, CF_STAIRS ) then
      Exit( HandleCommand( TCommand.Create( COMMAND_ENTER ) ) )
    else
    begin
      iItem := Level.Item[ Player.Position ];
      if ( iItem <> nil ) and ( iItem.isLever ) then
        Exit( HandleCommand( TCommand.Create( COMMAND_USE, iItem ) ) );
    end;
  end;

  if ( aCommand = INPUT_OPEN ) then
  begin
    iID := 'open';
    iFlag := CF_OPENABLE;
  end;

  if ( aCommand = INPUT_CLOSE ) then
  begin
    iID := 'close';
    iFlag := CF_CLOSABLE;
  end;

  iCount := 0;
  if iFlag = 0 then
  begin
    for iScan in NewArea( Player.Position, 1 ).Clamped( Level.Area ) do
      if ( iScan <> Player.Position ) and ( Level.cellFlagSet(iScan, CF_OPENABLE) or Level.cellFlagSet(iScan, CF_CLOSABLE) ) then
      begin
        Inc(iCount);
        iTarget := iScan;
      end;
  end
  else
    for iScan in NewArea( Player.Position, 1 ).Clamped( Level.Area ) do
      if Level.cellFlagSet( iScan, iFlag ) and Level.isEmpty( iScan ,[EF_NOITEMS,EF_NOBEINGS] ) then
      begin
        Inc(iCount);
        iTarget := iScan;
      end;

  if iCount = 0 then
  begin
    if iID = ''
      then UI.Msg( 'There''s nothing you can act upon here.' )
      else UI.Msg( 'There''s no door you can %s here.', [ iID ] );
    Exit( False );
  end;

  if iCount > 1 then
  begin
    if iID = ''
      then iDir := UI.ChooseDirection('action')
      else iDir := UI.ChooseDirection(Capitalized(iID)+' door');
    if iDir.code = DIR_CENTER then Exit( False );
    iTarget := Player.Position + iDir;
  end;

  if Level.isProperCoord( iTarget ) then
  begin
    if ( (iFlag <> 0) and Level.cellFlagSet( iTarget, iFlag ) ) or
        ( (iFlag = 0) and ( Level.cellFlagSet( iTarget, CF_CLOSABLE ) or Level.cellFlagSet( iTarget, CF_OPENABLE ) ) ) then
    begin
      if not Level.isEmpty( iTarget ,[EF_NOITEMS,EF_NOBEINGS] ) then
      begin
        UI.Msg( 'There''s something in the way!' );
        Exit( False );
      end;
      // SUCCESS
      Exit( HandleCommand( TCommand.Create( COMMAND_ACTION, iTarget ) ) );
    end;
    if iID = ''
      then UI.Msg( 'You can''t do that!' )
      else UI.Msg( 'You can''t %s that.', [ iID ] );
  end;
  Exit( False );
end;

function TDoom.HandleMoveCommand( aCommand : Byte ) : Boolean;
var iDir        : TDirection;
    iTarget     : TCoord2D;
    iMoveResult : TMoveResult;
begin
  Player.FLastTargetPos.Create(0,0);
  if BF_SESSILE in FFlags then
  begin
    UI.Msg( 'You can''t!' );
    Exit( False );
  end;

  iDir := InputDirection( aCommand );
  iTarget := Player.Position + iDir;
  iMoveResult := Player.TryMove( iTarget );

  if (not Player.FPathRun) and Player.FRun.Active and (
       ( Player.FRun.Count >= Option_MaxRun ) or
       ( iMoveResult <> MoveOk ) or
       Level.cellFlagSet( iTarget, CF_NORUN ) or
       (not Level.isEmpty(iTarget,[EF_NOTELE]))
     ) then
  begin
    Player.FPathRun := False;
    Player.FRun.Stop;
    Exit( False );
  end;

  case iMoveResult of
     MoveBlock :
       begin
         if Level.isProperCoord( iTarget ) and Level.cellFlagSet( iTarget, CF_PUSHABLE ) then
           Exit( HandleCommand( TCommand.Create( COMMAND_ACTION, iTarget ) ) )
         else
         begin
           if Option_Blindmode then UI.Msg( 'You bump into a wall.' );
           Exit( False );
         end;
       end;
     MoveBeing : Exit( HandleCommand( TCommand.Create( COMMAND_MELEE, iTarget ) ) );
     MoveDoor  : Exit( HandleCommand( TCommand.Create( COMMAND_ACTION, iTarget ) ) );
     MoveOk    : Exit( HandleCommand( TCommand.Create( COMMAND_MOVE, iTarget ) ) );
  end;
  Exit( False );
end;

function TDoom.HandleFireCommand( aAlt : Boolean; aMouse : Boolean ) : Boolean;
var iDir        : TDirection;
    iTarget     : TCoord2D;
    iItem       : TItem;
    iFireDesc   : AnsiString;
    iChainFire  : Byte;
    iAltFire    : TAltFire;
    iLimitRange : Boolean;
    iRange      : Byte;
begin
  iChainFire := Player.ChainFire;
  Player.ChainFire := 0;

  iItem := Player.Inv.Slot[ efWeapon ];
  if (iItem = nil) or (not iItem.isWeapon) then
  begin
    UI.Msg( 'You have no weapon.' );
    Exit( False );
  end;
  if not aAlt then
  begin
    if (not aMouse) and iItem.isMelee then
    begin
      iDir := UI.ChooseDirection('Melee attack');
      if (iDir.code = DIR_CENTER) then Exit( False );
      iTarget := Player.Position + iDir;
      Exit( HandleCommand( TCommand.Create( COMMAND_MELEE, iTarget ) ) );
    end;

    if (not iItem.isRanged) then
    begin
      UI.Msg( 'You have no ranged weapon.' );
      Exit( False );
    end;
  end
  else
  begin
    if iItem.AltFire = ALT_NONE then
    begin
      UI.Msg( 'This weapon has no alternate fire mode' );
      Exit( False );
    end;
  end;
  if not iItem.CallHookCheck( Hook_OnFire, [Self,aAlt] ) then Exit( False );

  if aAlt then
  begin
    if iItem.isMelee and ( iItem.AltFire = ALT_THROW ) then
    begin
      if not aMouse then
      begin
        iRange      := Missiles[ iItem.Missile ].Range;
        iLimitRange := MF_EXACT in Missiles[ iItem.Missile ].Flags;
        if not Player.doChooseTarget( 'Throw -- Choose target...', iRange, iLimitRange ) then
        begin
          UI.Msg( 'Throwing canceled.' );
          Exit( False );
        end;
        iTarget := Player.TargetPos;
      end
      else
        iTarget  := IO.MTarget;
    end;
  end;

  if iItem.isRanged then
  begin
    if not iItem.Flags[ IF_NOAMMO ] then
    begin
      if iItem.Ammo = 0              then Exit( Player.FailConfirm( 'Your weapon is empty.', [] ) );
      if iItem.Ammo < iItem.ShotCost then Exit( Player.FailConfirm( 'You don''t have enough ammo to fire the %s!', [iItem.Name]) );
    end;

    if iItem.Flags[ IF_CHAMBEREMPTY ] then Exit( Player.FailConfirm( 'Shell chamber empty - move or reload.', [] ) );


    if iItem.Flags[ IF_SHOTGUN ] then
      iRange := Shotguns[ iItem.Missile ].Range
    else
      iRange := Missiles[ iItem.Missile ].Range;
    if iRange = 0 then iRange := Player.Vision;

    iLimitRange := (not iItem.Flags[ IF_SHOTGUN ]) and (MF_EXACT in Missiles[ iItem.Missile ].Flags);
    if not aMouse then
    begin
      iAltFire    := ALT_NONE;
      if aAlt then iAltFire := iItem.AltFire;
      iFireDesc := '';
      case iAltFire of
        ALT_SCRIPT  : iFireDesc := LuaSystem.Get([ 'items', iItem.ID, 'altname' ],'');
        ALT_AIMED   : iFireDesc := 'aimed';
        ALT_SINGLE  : iFireDesc := 'single';
      end;
      if iFireDesc <> '' then iFireDesc := ' (@Y'+iFireDesc+'@>)';

      if iAltFire = ALT_CHAIN then
      begin
        case iChainFire of
          0 : iFireDesc := ' (@Ginitial@>)';
          1 : iFireDesc := ' (@Ywarming@>)';
          2 : iFireDesc := ' (@Rfull@>)';
        end;
        if not Player.doChooseTarget( Format('Chain fire%s -- Choose target or abort...', [ iFireDesc ]), iRange, iLimitRange ) then
          Exit( Player.Fail( 'Targeting canceled.', [] ) );
      end
      else
        if not Player.doChooseTarget( Format('Fire%s -- Choose target...',[ iFireDesc ]), iRange, iLimitRange ) then
          Exit( Player.Fail( 'Targeting canceled.', [] ) );
      iTarget := Player.TargetPos;
    end
    else
    begin
      iTarget := IO.MTarget;
    end;
    if iLimitRange then
      if Distance( Player.Position, iTarget ) > iRange then
        Exit( Player.Fail( 'Out of range!', [] ) );
  end;

  Player.ChainFire := iChainFire;
  if aAlt
    then Exit( HandleCommand( TCommand.Create( COMMAND_ALTFIRE, iTarget, iItem ) ) )
    else Exit( HandleCommand( TCommand.Create( COMMAND_FIRE, iTarget, iItem ) ) );
end;


function TDoom.HandleUnloadCommand : Boolean;
var iID         : AnsiString;
    iName       : AnsiString;
    iItem       : TItem;
    iItemTypes  : TItemTypeSet;
begin
  iItemTypes := [ ItemType_Ranged, ItemType_AmmoPack ];
  if (BF_SCAVENGER in FFlags) then
    iItemTypes := [ ItemType_Ranged, ItemType_AmmoPack, ItemType_Melee, ItemType_Armor, ItemType_Boots ];
  iItem := Level.Item[ Player.Position ];
  if (iItem = nil) or ( not (iItem.IType in iItemTypes) ) then
  begin
    iItem := Player.Inv.Choose( iItemTypes, 'unload' );
    if iItem = nil then Exit( False );
  end;
  iName := iItem.Name;

  if iItem.isAmmoPack then
    if not UI.MsgConfirm('An ammopack might serve better in the Prepared slot. Continuing will unload the ammo destroying the pack. Are you sure?', True)
      then Exit( False );

  if (not iItem.isAmmoPack) and (BF_SCAVENGER in FFlags) and
    ((iItem.Ammo = 0) or iItem.Flags[ IF_NOUNLOAD ] or iItem.Flags[ IF_RECHARGE ] or iItem.Flags[ IF_NOAMMO ]) and
    (iItem.Flags[ IF_EXOTIC ] or iItem.Flags[ IF_UNIQUE ] or iItem.Flags[ IF_ASSEMBLED ] or iItem.Flags[ IF_MODIFIED ]) then
  begin
    iID := LuaSystem.ProtectedCall( ['DoomRL','OnDisassemble'], [ iItem ] );
    if iID <> '' then
      if not UI.MsgConfirm('Do you want to disassemble the '+iName+'?', True) then
        iID := '';
  end;

  if ( iID = '' ) and ( not( iItem.IType in [ ItemType_Ranged, ItemType_AmmoPack ] ) ) then
     Exit( False );

  Exit( HandleCommand( TCommand.Create( COMMAND_UNLOAD, iItem, iID ) ) );
end;

function TDoom.HandleSwapWeaponCommand : Boolean;
begin
  if ( Player.Inv.Slot[ efWeapon ] <> nil )  and ( Player.Inv.Slot[ efWeapon ].Flags[ IF_CURSED ] ) then begin UI.Msg('You can''t!'); Exit( False ); end;
  if ( Player.Inv.Slot[ efWeapon2 ] <> nil ) and ( Player.Inv.Slot[ efWeapon2 ].isAmmoPack )        then begin UI.Msg('Nothing to swap!'); Exit( False ); end;
  Exit( HandleCommand( TCommand.Create( COMMAND_SWAPWEAPON ) ) );
end;

function TDoom.HandleCommand( aCommand : TCommand ) : Boolean;
begin
  if aCommand.Command = COMMAND_NONE then
    Exit( False );
  UI.MsgUpDate;
try
  Player.HandleCommand( aCommand );
except
  on e : Exception do
  begin
    if CRASHMODE then raise;
    ErrorLogOpen('CRITICAL','Player action exception!');
    ErrorLogWriteln('Error message : '+e.Message);
    ErrorLogClose;
    UI.ErrorReport(e.Message);
    CRASHMODE := True;
  end;
end;

  if State <> DSPlaying then Exit( False );
  UI.Focus( Player.Position );
  Player.UpdateVisual;
  while (Player.SCount < 5000) and (State = DSPlaying) do
  begin
    FLevel.CalculateVision( Player.Position );
    FLevel.Tick;
    UI.WaitForAnimation;
    if not Player.PlayerTick then Exit( True );
  end;
  PreAction;
  Exit( True );
end;


function TDoom.HandleMouseEvent( aEvent : TIOEvent ) : Boolean;
var iPoint   : TIOPoint;
    iAlt     : Boolean;
    iButton  : TIOMouseButton;
begin
  iPoint := SpriteMap.DevicePointToCoord( aEvent.Mouse.Pos );
  IO.MTarget.Create( iPoint.X, iPoint.Y );
  if Doom.Level.isProperCoord( IO.MTarget ) then
  begin
    iButton  := aEvent.Mouse.Button;
    iAlt     := False;
    if iButton in [ VMB_BUTTON_LEFT, VMB_BUTTON_RIGHT ] then
      iAlt := VKMOD_ALT in IO.Driver.GetModKeyState;

    if iButton = VMB_BUTTON_MIDDLE then
      if IO.MTarget = Player.Position
        then Exit( HandleSwapWeaponCommand )
        else Exit( HandleCommand( Player.Inv.RunEq ) );

    if iButton = VMB_BUTTON_LEFT then
    begin
      if IO.MTarget = Player.Position then
        if iAlt then
          Exit( HandleCommand( Player.Inv.View ) )
        else
        if Level.cellFlagSet( Player.Position, CF_STAIRS ) then
          Exit( HandleCommand( TCommand.Create( COMMAND_ENTER ) ) )
        else
          if Level.Item[ Player.Position ] <> nil then
            if Level.Item[ Player.Position ].isLever then
              Exit( HandleCommand( TCommand.Create( COMMAND_USE, Level.Item[ Player.Position ] ) ) )
            else
              Exit( HandleCommand( TCommand.Create( COMMAND_PICKUP ) ) )
          else
            Exit( HandleCommand( Player.Inv.View ) )
      else
      if Distance( Player.Position, IO.MTarget ) = 1
        then Exit( HandleMoveCommand( DirectionToInput( NewDirection( Player.Position, IO.MTarget ) ) ) )
        else if Level.isExplored( IO.MTarget ) then
        begin
          if not Player.RunPath( IO.MTarget ) then
          begin
            UI.Msg('Can''t get there!');
            Exit;
          end;
        end
        else
        begin
          UI.Msg('You don''t know how to get there!');
          Exit;
        end;
    end;

    if iButton = VMB_BUTTON_RIGHT then
    begin
      if (IO.MTarget = Player.Position) or
        ((Player.Inv.Slot[ efWeapon ] <> nil) and (Player.Inv.Slot[ efWeapon ].isRanged) and (not (Player.Inv.Slot[efWeapon].GetFlag(IF_NOAMMO))) and (Player.Inv.Slot[ efWeapon ].Ammo = 0))  then
      begin
        if iAlt
          then Exit( HandleCommand( TCommand.Create( COMMAND_ALTRELOAD ) ) )
          else Exit( HandleCommand( TCommand.Create( COMMAND_RELOAD ) ) );
      end
      else if (Player.Inv.Slot[ efWeapon ] <> nil) and (Player.Inv.Slot[ efWeapon ].isRanged) then
      begin
        if iAlt
          then Exit( HandleFireCommand( True, True ) )
          else Exit( HandleFireCommand( False, True ) );
      end
      else Exit( HandleCommand( TCommand.Create( COMMAND_MELEE,
        Player.Position + NewDirectionSmooth( Player.Position, IO.MTarget )
      ) ) );
    end;

    if iButton in [ VMB_WHEEL_UP, VMB_WHEEL_DOWN ] then
      Exit( HandleCommand( Player.Inv.DoScrollSwap ) );
  end;
  Exit( False );
end;

function TDoom.HandleKeyEvent( aEvent : TIOEvent ) : Boolean;
var iCommand : Byte;
begin
  IO.KeyCode := IOKeyEventToIOKeyCode( aEvent.Key );
  iCommand := Config.Commands[ IO.KeyCode ];
  if ( iCommand = 255 ) then // GodMode Keys
  begin
    Config.RunKey( IO.KeyCode );
    Action( 0 );
    Exit( True );
  end;
  if iCommand > 0 then
  begin
    // Handle commands that should be handled by the UI
    // TODO: Fix
    case iCommand of
      INPUT_ESCAPE     : begin if GodMode then Doom.SetState( DSQuit ); Exit; end;
      INPUT_LOOK       : begin UI.Msg( '-' ); UI.LookMode; Exit; end;
      INPUT_PLAYERINFO : begin Player.doScreen; Exit; end;
      INPUT_QUIT       : begin Player.doQuit; Exit; end;
      INPUT_HELP       : begin Help.Run; Exit; end;
      INPUT_MESSAGES   : begin IO.RunUILoop( TUIMessagesViewer.Create( IO.Root, UI.MsgGetRecent ) ); Exit; end;
      INPUT_ASSEMBLIES : begin IO.RunUILoop( TUIAssemblyViewer.Create( IO.Root ) ); Exit; end;
      INPUT_HARDQUIT   : begin
        Option_MenuReturn := False;
        Player.doQuit(True);
        Exit;
      end;
      INPUT_SAVE      : begin Player.doSave; Exit; end;
      INPUT_TRAITS    : begin IO.RunUILoop( TUITraitsViewer.Create( IO.Root, @Player.FTraits, Player.ExpLevel ) );Exit; end;
      INPUT_RUNMODE   : begin Player.doRun;Exit; end;

      INPUT_EXAMINENPC   : begin Player.ExamineNPC; Exit; end;
      INPUT_EXAMINEITEM  : begin Player.ExamineItem; Exit; end;
      INPUT_GRIDTOGGLE: begin if GraphicsVersion then SpriteMap.ToggleGrid; Exit; end;
      INPUT_SOUNDTOGGLE  : begin SoundOff := not SoundOff; Exit; end;
      INPUT_MUSICTOGGLE  : begin
                               MusicOff := not MusicOff;
                               if MusicOff then IO.Audio.PlayMusic('')
                                           else IO.Audio.PlayMusic(Level.ID);
                               Exit;
                             end;
    end;
    Exit( Action( iCommand ) );
  end;
  Exit( False );
end;


procedure TDoom.Run;
var iRank       : THOFRank;
    iResult     : TMenuResult;
    iEvent      : TIOEvent;
    iCommand    : Byte;
begin
  iResult    := TMenuResult.Create;
  Doom.Load;

  if not FileExists( WritePath + 'doom.prc' ) then DoomFirst;

  IO.RunUILoop( TMainMenuViewer.CreateMain( IO.Root ) );
  if FState <> DSQuit then
    IO.RunUILoop( TMainMenuViewer.CreateDonator( IO.Root ) );
  if FState <> DSQuit then
repeat
  if not DataLoaded then
    Doom.Load;
  IO.LoadStop;

  StatusEffect   := StatusNormal;
  Difficulty     := 2;
  ArchAngel      := False;
  Challenge      := '';
  SChallenge     := '';
  GameWon        := False;
  Module         := nil;
  NoPlayerRecord := False;
  NoScoreRecord  := False;

  UI.ClearAllMessages;

  IO.Audio.PlayMusicOnce('start');
  SetState( DSMenu );
  iResult.Reset; // TODO : could reuse for same game!
  IO.RunUILoop( TMainMenuViewer.Create( IO.Root, iResult ) );
  Apply( iResult );
  if State = DSQuit then Break;

  if iResult.Loaded then
  begin
    SetState( DSLoading );
    SetupLuaConstants;
  end
  else
  begin
    SetupLuaConstants;
    LoadChallenge;
    CreatePlayer( iResult );
  end;

  LuaSystem.SetValue('level', Level );

  if GameType = GameEpisode then LoadModule( False );

  if (not (State = DSLoading)) then
    CallHookCheck( Hook_OnIntro, [Option_NoIntro] );


  if (GameType <> GameSingle) and (State <> DSLoading) then
  begin
    CallHook( Hook_OnCreateEpisode, [] );
  end;
  CallHook( Hook_OnLoaded, [State = DSLoading] );

  GameRealTime := MSecNow();
  try
  repeat
    if Player.NukeActivated > 0 then
    begin
      UI.Msg('You hear a gigantic explosion above!');
      Inc(Player.FScore,1000);
      Player.IncStatistic('levels_nuked');
      Player.NukeActivated := 0;
    end;

    with Player do
    begin
      FStatistics.Update;
    end;

    if GameType = GameSingle then
       RunSingle
    else
    begin
      if Player.SpecExit = '' then
        Inc(Player.CurrentLevel)
      else
        Player.IncStatistic('bonus_levels_visited');

      with LuaSystem.GetTable(['player','episode',Player.CurrentLevel]) do
      try
        FLevel.Init(getInteger('style',0),
                   getInteger('number',0),
                   getString('name',''),
                   getString('special',''),
                   Player.CurrentLevel,
                   getInteger('danger',0));

        if Player.SpecExit <> ''
          then FLevel.Flags[ LF_BONUS ] := True
          else Player.SpecExit := getString('script','');

      finally
        Free;
      end;

      if Player.SpecExit <> ''
        then
          FLevel.ScriptLevel(Player.SpecExit)
        else
        begin
          if FLevel.Name_Number <> 0 then UI.Msg('You enter %s, level %d.',[ FLevel.Name, FLevel.Name_Number ]);
          CallHookCheck(Hook_OnGenerate,[]);
          FLevel.AfterGeneration( True );
        end;
      Player.SpecExit := '';
    end;
    
    FLevel.CalculateVision( Player.Position );
    SetState( DSPlaying );
    UI.BloodSlideDown(20);
    
    IO.Audio.PlayMusic(FLevel.ID);
    FLevel.PreEnter;

    FLevel.Tick;
    PreAction;

    while ( State = DSPlaying ) do
    begin
      if Player.ChainFire > 0 then
      begin
        Action( COMMAND_ALTFIRE );
        Continue;
      end;

      if ( Player.FRun.Active ) then
      begin
        iCommand := Player.GetRunInput;
        if iCommand <> 0 then
          Action( iCommand );
        Continue;
      end;

      repeat
        while not IO.Driver.EventPending do
        begin
          IO.FullUpdate;
          IO.Driver.Sleep(10);
        end;
        if not IO.Driver.PollEvent( iEvent ) then continue;
        if IO.Root.OnEvent( iEvent ) then iEvent.EType := VEVENT_KEYUP;
        if (iEvent.EType = VEVENT_SYSTEM) and (iEvent.System.Code = VIO_SYSEVENT_QUIT) then
          break;
      until ( iEvent.EType = VEVENT_KEYDOWN ) or ( GraphicsVersion and ( iEvent.EType = VEVENT_MOUSEDOWN ) );

      if (iEvent.EType = VEVENT_SYSTEM) then
      begin
        if Option_LockClose
           then Action( INPUT_QUIT )
           else Action( INPUT_HARDQUIT );
        Continue;
      end;

      if iEvent.EType = VEVENT_MOUSEDOWN then
        HandleMouseEvent( iEvent );

      if iEvent.EType = VEVENT_KEYDOWN then
        HandleKeyEvent( iEvent );
    end;

    if State in [ DSNextLevel, DSSaving ] then
      FLevel.Leave;

    Inc(Player.FScore,100);
    if GameWon and (State <> DSNextLevel) then Player.WriteMemorial;
    FLevel.Clear;
    UI.SetHint('');
  until (State <> DSNextLevel) or (GameType = GameSingle);
  except on e : Exception do
  begin
    EmitCrashInfo( e.Message, True );
    EXCEPTEMMITED := True;
    if Option_SaveOnCrash and ((Player.FStatistics.Map['crash_count'] = 0) or{thelaptop: Vengeance is MINE} (Doom.Difficulty < DIFF_NIGHTMARE)) then
    begin
      if Player.CurrentLevel <> 1 then Dec(Player.CurrentLevel);
      Player.IncStatistic('crash_count');
      Player.SpecExit := '';
      WriteSaveFile;
    end;
    raise;
  end;
  end;

  if GameType <> GameSingle then
  begin
    if State = DSSaving then
    begin
      WriteSaveFile;
      UI.MsgEnter('Game saved. Press <Enter> to exit.');
    end;
    if State = DSFinished then
    begin
      if GameWon then
      begin
        IO.Audio.PlayMusic('victory');
        CallHookCheck(Hook_OnWinGame,[]);
      end
      else IO.Audio.PlayMusic('bunny');
    end;
  end;

  if GameType = GameStandard then
  begin
    if State = DSFinished then
    begin
      if HOF.RankCheck( iRank ) then
        IO.RunUILoop( TUIRankUpViewer.Create( IO.Root, iRank ) );
      if Player.FScore >= -1000 then
        IO.RunUILoop( TUIMortemViewer.Create( IO.Root ) );
      IO.RunUILoop( TUIHOFViewer.Create( IO.Root, HOF.GetHOFReport ) );
    end;
    CallHook(Hook_OnUnLoad,[]);
  end
  else
    if (State <> DSSaving) and (State <> DSQuit) then
    begin
      Player.WriteMemorial;
      if Player.FScore >= -1000 then
        IO.RunUILoop( TUIMortemViewer.Create( IO.Root ) );
    end;

  UI.BloodSlideDown(20);
  FreeAndNil(Player);

  if GameType <> GameStandard then
    Doom.UnLoad;

until not Option_MenuReturn;
  FreeAndNil( iResult );
end;

procedure TDoom.CreatePlayer ( aResult : TMenuResult ) ;
begin
  FreeAndNil( UIDs );
  UIDs := Systems.Add(TUIDStore.Create) as TUIDStore;
  Player := TPlayer.Create;
  FLevel.Place( Player, NewCoord2D(4,4) );
  Player.Klass := aResult.Klass;

  if Option_AlwaysName <> '' then
    Player.Name := Option_AlwaysName
  else
    if (Option_AlwaysRandomName) or (aResult.Name = '')
      then Player.Name := LuaSystem.ProtectedCall(['DoomRL','random_name'],[])
      else Player.Name := aResult.Name;

  LuaSystem.ProtectedCall(['klasses',Player.Klass,'OnPick'], [ Player ] );
  CallHook(Hook_OnCreatePlayer,[]);
  Player.FTraits.Upgrade( aResult.Trait );
  Player.UpdateVisual;
end;

function TDoom.LoadSaveFile: Boolean;
var Stream : TStream;
begin
  try
    try
      Stream := TGZFileStream.Create( WritePath + 'save',gzOpenRead );

      ModuleID        := Stream.ReadAnsiString;
      UIDs            := TUIDStore.CreateFromStream( Stream );
      GameType        := TDoomGameType( Stream.ReadByte );
      GameWon         := Stream.ReadByte <> 0;
      Difficulty      := Stream.ReadByte;
      Challenge       := Stream.ReadAnsiString;
      ArchAngel       := Stream.ReadByte <> 0;
      SChallenge      := Stream.ReadAnsiString;

      Player := TPlayer.CreateFromStream( Stream );
    finally
      Stream.Destroy;
    end;
    DeleteFile( WritePath + 'save' );

    if GameType <> GameStandard then
    begin
      Module := Modules.FindLocalRawMod( ModuleID );
      if Module = nil then Module := Modules.FindLocalMod( ModuleID );
      if Module = nil then raise TModuleException.Create( 'Module '+ModuleID+' used by the savefile not found!' );
      NoPlayerRecord := True;
      NoScoreRecord  := True;
    end;
    UI.Msg('Game loaded.');

    if Player.Dead then
      raise EException.Create('Player in save file is dead anyway.');
    LoadChallenge;
    LoadSaveFile := True;
  except
    on e : Exception do
    begin
      Log('Save file corrupted! Error while loading : '+ e.message );
      DeleteFile( WritePath + 'save' );
      LoadSaveFile := False;
    end;
  end;
end;

procedure TDoom.WriteSaveFile;
var Stream : TStream;
begin
  Player.FStatistics.RealTime += MSecNow() - GameRealTime;
  Player.IncStatistic('save_count');

  Stream := TGZFileStream.Create( WritePath + 'save',gzOpenWrite );

  Stream.WriteAnsiString( ModuleID );
  UIDs.WriteToStream( Stream );
  Stream.WriteByte( Byte(GameType) );
  if GameWon   then Stream.WriteByte( 1 ) else Stream.WriteByte( 0 );
  Stream.WriteByte( Difficulty );
  Stream.WriteAnsiString( Challenge );
  if ArchAngel then Stream.WriteByte( 1 ) else Stream.WriteByte( 0 );
  Stream.WriteAnsiString( SChallenge );

  Player.WriteToStream(Stream);

  FreeAndNil( Stream );
end;

function TDoom.SaveExists : Boolean;
begin
  Exit( FileExists( WritePath + 'save' ) );
end;

procedure TDoom.SetupLuaConstants;
begin
  LuaSystem.SetValue('DIFFICULTY', Difficulty);
  LuaSystem.SetValue('CHALLENGE',  Challenge);
  LuaSystem.SetValue('SCHALLENGE', SChallenge);
  LuaSystem.SetValue('ARCHANGEL', ArchAngel);
end;

procedure TDoom.DoomFirst;
var T : Text;
begin
  Assign(T, WritePath + 'doom.prc');
  Rewrite(T);
  Writeln(T,'Doom was already run.');
  Close(T);
  IO.RunUILoop( TMainMenuViewer.CreateFirst( IO.Root ) );
end;

procedure TDoom.RunSingle;
begin
  FLevel.Init(1,1,'','',1,1);
  Player.SpecExit := '';
  ModuleID := Module.Id;
  LoadModule( False );
  FLevel.SingleLevel(Module.Id);
end;

destructor TDoom.Destroy;
begin
  UnLoad;
  Log('Doom destroyed.');
  FreeAndNil( IO );
  inherited Destroy;
end;

end.

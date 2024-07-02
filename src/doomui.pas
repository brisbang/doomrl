{$include doomrl.inc}
unit doomui; 
interface
uses sysutils, vgltypes, vglimage, vimage, vrltools, vconui, viotypes,
     vuiconsole, vuielement, vuitypes, vioevent, vtextmap, vrlmsg;

type TDoomGameUI = class( TUIElement )
  constructor Create( aParent : TUIElement; const aArea : TUIRect );
  procedure OnRedraw; override;
  procedure OnRender; override;
  procedure OnUpdate( aTime : DWord ); override;
  function OnMouseDown( const event : TIOMouseEvent ) : Boolean; override;
  function OnMouseMove( const event : TIOMouseMoveEvent ) : Boolean; override;
  procedure SetTarget( aTarget : TCoord2D; aTargetColor : TUIColor; aTargetRange : Byte = 100 );
  procedure SetLastTarget( aLastTarget : TCoord2D );
  procedure ResetTarget;
  procedure UpdateMinimap;
  procedure SetMinimapScale( aScale : Byte );
  destructor Destroy; override;
private
  function Chunkify( const aString : AnsiString; aStart : Integer; aColor : TIOColor ) : TUIChunkBuffer;
private
  FLastMouse: DWord;
  FTime     : DWord;
  FHint     : TUIString;
  FMessages : TRLMessages;
  FMap      : TTextMap;
  FMouseLock: Boolean;

  FTargetLast     : Boolean;
  FTarget         : TCoord2D;
  FTargetRange    : Byte;
  FTargetEnabled  : Boolean;

  FMinimapImage   : TImage;
  FMinimapTexture : DWord;
  FMinimapScale   : Integer;
  FMinimapGLPos   : TGLVec2i;
public
  property Hint     : TUIString   read FHint write FHint;
  property Messages : TRLMessages read FMessages;
  property Map      : TTextMap    read FMap;
end;


implementation

uses math, dfoutput,
     vtig, vcolor, vmath, vutil,
     dfdata, dflevel, dfitem, dfbeing, dfplayer,
     doomio, doomspritemap, doombase, vvision;

{ TDoomGameUI }

constructor TDoomGameUI.Create ( aParent : TUIElement; const aArea : TUIRect );
begin
  inherited Create( aParent, aArea );
  if GraphicsVersion then
    FEventFilter := [ VEVENT_MOUSEDOWN, VEVENT_MOUSEMOVE ];
  FFullScreen    := True;
  FTargetEnabled := False;
  FMap      := nil;
  FTime     := 0;
  if not GraphicsVersion then
    FMap := TTextMap.Create( IO.Console, Rectangle( 2,3,MAXX,MAXY ) );


  // Self, Rectangle( 1,0,FAbsolute.w-3,2 ),
  //FMessages.ForeColor := DarkGray;

  FMessages := TRLMessages.Create(2, @IO.EventWaitForMore, @Chunkify, Option_MessageBuffer );

  FHint     := '';
  FEnabled := False;
  FMouseLock := True;

  FMinimapScale    := 0;
  FMinimapTexture  := 0;
  FMinimapGLPos    := TGLVec2i.Create( 0, 0 );
  FMinimapImage    := nil;

  if GraphicsVersion then
  begin
    FMinimapImage    := TImage.Create( 128, 32 );
    FMinimapImage.Fill( NewColor( 0,0,0,0 ) );
    SetMinimapScale( IO.MiniScale );
  end;

end;

procedure TDoomGameUI.OnRedraw;
const UnitTex : TGLVec2f = ( Data : ( 1, 1 ) );
      ZeroTex : TGLVec2f = ( Data : ( 0, 0 ) );
var iCount      : DWord;
    i, iMax     : DWord;
    iCon        : TUIConsole;
    iColor      : TUIColor;
    iHPP        : Integer;
    iPos        : TUIPoint;
    iBottom     : Integer;
    iTargetLine : TVisionRay;
    iCurrent    : TCoord2D;
    iLevel      : TLevel;

  function ArmorColor( aValue : Integer ) : TUIColor;
  begin
    case aValue of
     -100.. 25  : Exit(LightRed);
      26 .. 49  : Exit(Yellow);
      50 ..1000 : Exit(LightGray);
      else Exit(LightGray);
    end;
  end;
  function NameColor( aValue : Integer ) : TUIColor;
  begin
    case aValue of
     -100.. 25  : Exit(LightRed);
      26 .. 49  : Exit(Yellow);
      50 ..1000 : Exit(LightBlue);
      else Exit(LightGray);
    end;
  end;
  function WeaponColor( aWeapon : TItem ) : TUIColor;
  begin
    if aWeapon.IType = ITEMTYPE_MELEE then Exit(lightgray);
    if ( aWeapon.Ammo = 0 ) and not ( aWeapon.Flags[ IF_NOAMMO ] ) then Exit(LightRed);
    Exit(LightGray);
  end;
  function ExpString : AnsiString;
  begin
    if Player.ExpLevel >= MaxPlayerLevel - 1 then Exit('MAX');
    Exit(IntToStr(Clamp(Floor(((Player.Exp-ExpTable[Player.ExpLevel]) / (ExpTable[Player.ExpLevel+1]-ExpTable[Player.ExpLevel]))*100),0,99))+'%');
  end;
  procedure Paint ( aCoord : TCoord2D; aColor : TUIColor; aChar : Char = ' ') ;
  var iPos        : TUIPoint;
  begin
    iPos := Point( aCoord.x + 1, aCoord.y + 2 );
    if aChar = ' ' then aChar := IO.Console.GetChar( iPos.X, iPos.Y );
    if StatusEffect = StatusInvert
       then VTIG_FreeChar( aChar, iPos, Black, LightGray )
       else VTIG_FreeChar( aChar, iPos, aColor );
  end;

begin
  iCon.Init( TConUIRoot(FRoot).Renderer );
  iCon.ClearRect( FAbsolute, Black );

  if Player <> nil then
  begin
    iPos    := Point( 2,23 );
    iBottom := 25;
    iHPP    := Round((Player.HP/Player.HPMax)*100);

    VTIG_FreeLabel( 'Armor :',                            iPos + Point(28,0), DarkGray );
    VTIG_FreeLabel( Player.Name,                          iPos + Point(1,0),  NameColor(iHPP) );
    VTIG_FreeLabel( 'Health:      Exp:   /      Weapon:', iPos + Point(1,1),  DarkGray );
    VTIG_FreeLabel( IntToStr(iHPP)+'%',                   iPos + Point(9,1),  Red );
    VTIG_FreeLabel( TwoInt(Player.ExpLevel),              iPos + Point(19,1), LightGray );
    VTIG_FreeLabel( ExpString,                            iPos + Point(22,1), LightGray );

    if Player.Inv.Slot[efWeapon] = nil
      then VTIG_FreeLabel( 'none',                                iPos + Point(36,1), LightGray )
      else VTIG_FreeLabel( Player.Inv.Slot[efWeapon].Description, iPos + Point(36,1), WeaponColor(Player.Inv.Slot[efWeapon]) );

    if Player.Inv.Slot[efTorso] = nil
      then VTIG_FreeLabel( 'none',                                iPos + Point(36,0), LightGray )
      else VTIG_FreeLabel( Player.Inv.Slot[efTorso].Description,  iPos + Point(36,0), ArmorColor(Player.Inv.Slot[efTorso].Durability) );

    iColor := Red;
    if Doom.Level.Empty then iColor := Blue;
    VTIG_FreeLabel( Doom.Level.Name, iPos + Point(61,2), iColor );
    if Doom.Level.Name_Number >= 100 then VTIG_FreeLabel( 'Lev'+IntToStr(Doom.Level.Name_Number), iPos + Point(73,2), iColor )
    else if Doom.Level.Name_Number <> 0 then VTIG_FreeLabel( 'Lev'+IntToStr(Doom.Level.Name_Number), iPos + Point(74,2), iColor );

    with Player do
    for iCount := 1 to MAXAFFECT do
      if FAffects.IsActive(iCount) then
      begin
        if FAffects.IsExpiring(iCount)
          then iColor := Affects[iCount].Color_exp
          else iColor := Affects[iCount].Color;
        VTIG_FreeLabel( Affects[iCount].name, Point( iPos.X+((Byte(iCount)-1)*4)+14, iBottom ), iColor )
      end;

    with Player do
      if (FTactic.Current = TacticRunning) and (FTactic.Count < 6) then
        VTIG_FreeLabel( TacticName[FTactic.Current], Point(iPos.x+1, iBottom ), Brown )
      else
        VTIG_FreeLabel( TacticName[FTactic.Current], Point(iPos.x+1, iBottom ), TacticColor[FTactic.Current] );
  end;
  if FHint <> '' then
    VTIG_FreeLabel( ' '+FHint+' ', Point( -1-Length( FHint ), 3 ), Yellow );

  if FTargetEnabled then
  begin
    iLevel := Doom.Level;
    if FTargetLast then
      Paint( Player.TargetPos, Yellow );
  { if range > PLight.Rad then range := Plight.rad;}
    if ( not GraphicsVersion ) and ( Player.Position <> FTarget ) then
    begin
      iColor := Green;
      iTargetLine.Init( iLevel, Player.Position, FTarget );
      repeat
        iTargetLine.Next;
        iCurrent := iTargetLine.GetC;
        if not iLevel.isProperCoord( iCurrent ) then Break;
        if not iLevel.isVisible( iCurrent ) then iColor := Red;
        if iColor = Green then if iTargetLine.Cnt > FTargetRange then icolor := Yellow;
        if iTargetLine.Done then Paint( iCurrent, iColor, 'X' )
                            else Paint( iCurrent, iColor, '*' );
        if iLevel.cellFlagSet( iCurrent, CF_BLOCKMOVE ) then iColor := Red;
      until (iTargetLine.Done) or (iTargetLine.cnt > 30);
    end;
  end;

  if GraphicsVersion and (FMinimapImage <> nil) and (FMinimapScale <> 0) then
    IO.QuadSheet.PushTexturedQuad( FMinimapGLPos, FMinimapGLPos + TGLVec2i.Create( FMinimapScale*128, FMinimapScale*32 ), ZeroTex, UnitTex, FMinimapTexture );

  if Assigned( FMap ) then
    FMap.OnRedraw;

  iCon.ClearRect( Rectangle( 1,0,FAbsolute.w-3,2 ), FBackColor );
  iMax := Min( LongInt( FMessages.Scroll+FMessages.VisibleCount ), FMessages.Content.Size );
  if FMessages.Content.Size > 0 then
  for i := 1+FMessages.Scroll to iMax do
  begin
    iColor := DarkGray;
    if i > iMax - FMessages.Active then iColor := LightGray;
    iCon.Print( FAbsolute.Pos + Point(0,i-1-FMessages.Scroll), FMessages.Content[ i-1 ], iColor, FBackColor, FAbsolute );
  end;

  {
  VTIG_Begin( 'messages', Point(78,2), Point( 1,1 ) );
  iMax := Min( LongInt( FMessages.Scroll+FMessages.VisibleCount ), FMessages.Content.Size );
  if FMessages.Content.Size > 0 then
  for i := 1+FMessages.Scroll to iMax do
  begin
    iColor := FForeColor;
    if i > iMax - FMessages.Active then iColor := iCon.BoldColor( FForeColor );
    for iChunk in FMessages.Content[ i-1 ] do
      VTIG_Text( iChunk.Content + ' ' );
//      VTIG_FreeLabel( iChunk.Content, iChunk.Position + Point(1,i-FMessages.Scroll) , iColor );
  end;
  VTIG_End;
  }
  inherited OnRedraw;
end;

procedure TDoomGameUI.OnRender;
var iRoot   : TConUIRoot;
    iP1,iP2 : TPoint;
begin
  if GraphicsVersion then
  begin
    iRoot := TConUIRoot(FRoot);
    iP1 := iRoot.ConsoleCoordToDeviceCoord( FAbsolute.Pos );
    iP2 := iRoot.ConsoleCoordToDeviceCoord( Point( FAbsolute.x2+1, FAbsolute.y+2 ) );
    IO.QuadSheet.PushColoredQuad( TGLVec2i.Create( iP1.x, iP1.y ), TGLVec2i.Create( iP2.x, iP2.y ), TGLVec4f.Create( 0,0,0,0.1 ) );

    iP1 := iRoot.ConsoleCoordToDeviceCoord( Point( FAbsolute.x, FAbsolute.y2-2 ) );
    iP2 := iRoot.ConsoleCoordToDeviceCoord( Point( FAbsolute.x2+1, FAbsolute.y2+2 ) );
    IO.QuadSheet.PushColoredQuad( TGLVec2i.Create( iP1.x, iP1.y ), TGLVec2i.Create( iP2.x, iP2.y ), TGLVec4f.Create( 0,0,0,0.1 ) );
  end;
  inherited OnRender;
end;

procedure TDoomGameUI.OnUpdate ( aTime : DWord ) ;
var iPoint   : TUIPoint;
    iValueX  : Single;
    iValueY  : Single;
    iActiveX : Integer;
    iActiveY : Integer;
    iMaxX    : Integer;
    iMaxY    : Integer;
    iShift   : TCoord2D;
begin
  FDirty := True;
  if GraphicsVersion then
  begin
    FTime += aTime;
    if FTime - FLastMouse > 3000 then
    begin
      IO.MCursor.Active := False;
      UI.SetTempHint('');
    end;

    if (IO.MCursor.Active) and IO.Driver.GetMousePos( iPoint ) and (not FMouseLock) then
    begin
      iMaxX   := IO.Driver.GetSizeX;
      iMaxY   := IO.Driver.GetSizeY;
      iValueX := 0;
      iValueY := 0;
      iActiveX := iMaxX div 8;
      iActiveY := iMaxY div 8;
      if iPoint.X < iActiveX      then iValueX := ((iActiveX -        iPoint.X) / iActiveX);
      if iPoint.X > iMaxX-iActiveX then iValueX := ((iActiveX -(iMaxX-iPoint.X)) /iActiveX);
      if iPoint.X < iActiveX then iValueX := -iValueX;
      if iMaxY < MAXY*IO.TileMult*32 then
      begin
        if iPoint.Y < iActiveY       then iValueY := ((iActiveY -        iPoint.Y) / iActiveY) / 2;
        if iPoint.Y > iMaxY-iActiveY then iValueY := ((iActiveY -(iMaxY-iPoint.Y)) /iActiveY) / 2;
        if iPoint.Y < iActiveY then iValueY := -iValueY;
      end;

      iShift := SpriteMap.Shift;
      if (iValueX <> 0) or (iValueY <> 0) then
      begin
        iShift := NewCoord2D(
          Clamp( SpriteMap.Shift.X + Ceil( iValueX * aTime ), SpriteMap.MinShift.X, SpriteMap.MaxShift.X ),
          Clamp( SpriteMap.Shift.Y + Ceil( iValueY * aTime ), SpriteMap.MinShift.Y, SpriteMap.MaxShift.Y )
        );
        SpriteMap.NewShift := iShift;
        FMouseLock :=
          ((iShift.X = SpriteMap.MinShift.X) or (iShift.X = SpriteMap.MaxShift.X))
       and ((iShift.Y = SpriteMap.MinShift.Y) or (iShift.Y = SpriteMap.MaxShift.Y));
      end;
    end;
  end;
  if Assigned( FMap ) then
    FMap.OnUpdate( aTime );
  inherited OnUpdate ( aTime ) ;
end;

function TDoomGameUI.OnMouseDown ( const event : TIOMouseEvent ) : Boolean;
begin
  if IO.MCursor <> nil then IO.MCursor.Active := True;
  FLastMouse := FTime;
  Exit( False );
end;

function TDoomGameUI.OnMouseMove ( const event : TIOMouseMoveEvent ) : Boolean;
begin
  if IO.MCursor <> nil then IO.MCursor.Active := True;
  FLastMouse := FTime;
  FMouseLock := False;
  Exit( False );
end;

procedure TDoomGameUI.SetTarget ( aTarget : TCoord2D; aTargetColor : TUIColor;
  aTargetRange : Byte ) ;
begin
  if GraphicsVersion and (SpriteMap <> nil) then
  begin
    SpriteMap.SetTarget( aTarget, NewColor( aTargetColor ), True );
    Exit;
  end;
  FTargetEnabled := True;
  FTarget        := aTarget;
  FTargetRange   := aTargetRange;
  // TODO: this clashes with TIG
  IO.Console.ShowCursor;
  IO.Console.MoveCursor( aTarget.x+1, aTarget.y+2 );
end;

procedure TDoomGameUI.SetLastTarget ( aLastTarget : TCoord2D ) ;
begin
  if not GraphicsVersion then
    FTargetLast := True;
end;

procedure TDoomGameUI.ResetTarget;
begin
  if GraphicsVersion and (SpriteMap <> nil) then
  begin
    SpriteMap.ClearTarget;
    Exit;
  end;
  FTargetEnabled := False;
end;

procedure TDoomGameUI.UpdateMinimap;
var x, y : DWord;
begin
  if (Doom.State = DSPlaying) and GraphicsVersion and (FMinimapImage <> nil) then
  begin
    for x := 0 to MAXX+1 do
      for y := 0 to MAXY+1 do
        FMinimapImage.ColorXY[x,y] := Doom.Level.GetMiniMapColor( NewCoord2D( x, y ) );
    if FMinimapTexture = 0
      then FMinimapTexture := UploadImage( FMinimapImage, False )
      else ReUploadImage( FMinimapTexture, FMinimapImage, False );
  end;
end;

procedure TDoomGameUI.SetMinimapScale ( aScale : Byte ) ;
begin
  if GraphicsVersion and (FMinimapImage <> nil) then
  begin
    FMinimapScale := aScale;
    FMinimapGLPos.Init( IO.Driver.GetSizeX - FMinimapScale*(MAXX+2) - 10, IO.Driver.GetSizeY - FMinimapScale*(MAXY+2) - ( 10 + IO.FontMult*20*3 ) );
    UpdateMinimap;
  end;
end;

destructor TDoomGameUI.Destroy;
begin
  FreeAndNil( FMap );
  FreeAndNil( FMinimapImage );
  inherited Destroy;
end;

function TDoomGameUI.Chunkify( const aString : AnsiString; aStart : Integer; aColor : TIOColor ) : TUIChunkBuffer;
var iCon       : TUIConsole;
    iChunkList : TUIChunkList;
    iPosition  : TUIPoint;
    iColor     : TUIColor;
begin
  iCon.Init( TConUIRoot(FRoot).Renderer );
  iPosition  := Point(aStart,0);
  iColor     := aColor;
  iChunkList := nil;
  iCon.ChunkifyEx( iChunkList, iPosition, iColor, aString, iColor, Dim );
  Exit( iCon.LinifyChunkList( iChunkList ) );
end;

end.


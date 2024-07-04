{$INCLUDE doomrl.inc}
unit doomio;
interface
uses {$IFDEF WINDOWS}Windows,{$ENDIF} Classes, SysUtils, vgenerics, vio,
     vsystems, vmath, vrltools, vluaconfig, vglquadrenderer, vgltypes,
     doomspritemap, doomviews, doomaudio,
     viotypes, vbitmapfont, vioevent, vioconsole, vuielement, vuitypes;

type TCommandSet = set of Byte;
     TKeySet     = set of Byte;

type TDoomOnProgress = procedure ( aProgress : DWord ) of object;


type TDoomIO = class( TIO )
  constructor Create; reintroduce;
  procedure Configure( aConfig : TLuaConfig; aReload : Boolean = False );
  function RunUILoop( aElement : TUIElement = nil ) : DWord; override;
  procedure FullUpdate; override;
  destructor Destroy; override;
  procedure Screenshot( aBB : Boolean );

  function EventWaitForMore : Boolean;

  procedure WADLoaded;
  procedure LoadStart( aAdd : DWord = 0 );
  function LoadCurrent : DWord;
  procedure LoadProgress( aProgress : DWord );
  procedure LoadStop;
  procedure Update( aMSec : DWord ); override;

  procedure WaitForEnter;
  function WaitForCommand( const aSet : TCommandSet ) : Byte;
  function WaitForKey( const aSet : TKeySet ) : Byte;
  procedure WaitForKeyEvent( out aEvent : TIOEvent; aMouseClick : Boolean = False; aMouseMove : Boolean = False );
  function CommandEventPending : Boolean;

  function OnEvent( const event : TIOEvent ) : Boolean; override;
private
  procedure ReuploadTextures;
  procedure CalculateConsoleParams;
  procedure GraphicsDraw;
  procedure ColorQuery(nkey,nvalue : Variant);
protected
  function FullScreenCallback( aEvent : TIOEvent ) : Boolean;
  function ScreenShotCallback( aEvent : TIOEvent ) : Boolean;
  function BBScreenShotCallback( aEvent : TIOEvent ) : Boolean;
public // REMOVE
  FMsgFont    : TBitmapFont;
private
  FAudio       : TDoomAudio;
  FTime        : QWord;
  FLastMouse   : QWord;
  FMouseLock   : Boolean;

  FLoading     : TUILoadingScreen;
  FMCursor     : TDoomMouseCursor;
  FQuadSheet   : TGLQuadList;
  FTextSheet   : TGLQuadList;
  FPostSheet   : TGLQuadList;
  FQuadRenderer: TGLQuadRenderer;
  FProjection  : TMatrix44;
  FSettings   : array [Boolean] of
  record
    Width  : Integer;
    Height : Integer;
    FMult  : Integer;
    TMult  : Integer;
    MiniM  : Integer;
  end;
  FMTarget     : TCoord2D;
  FVPadding    : DWord;
  FFontMult    : Byte;
  FTileMult    : Byte;
  FMiniScale   : Byte;
  FLinespace   : Word;
  FKeyCode     : TIOKeyCode;
  FLastTick    : TDateTime;
public
  property KeyCode   : TIOKeyCode read FKeyCode write FKeyCode;
  property QuadSheet : TGLQuadList read FQuadSheet;
  property TextSheet : TGLQuadList read FTextSheet;
  property PostSheet : TGLQuadList read FPostSheet;
  property MiniScale : Byte read FMiniScale;
  property FontMult  : Byte read FFontMult;
  property TileMult  : Byte read FTileMult;
  property MCursor   : TDoomMouseCursor read FMCursor;
  property MTarget   : TCoord2D read FMTarget write FMTarget;
  property Audio     : TDoomAudio read FAudio;
end;

var IO : TDoomIO;

procedure EmitCrashInfo( const aInfo : AnsiString; aInGame : Boolean  );

implementation

uses math, video, vlog, vdebug,
     variants, vdf, dateutils,
     vutil,
     vimage, vglimage,
     vuiconsole, vcolor,
     {$IFDEF WINDOWS}
     vtextio, vtextconsole,
     {$ELSE}
     vcursesio, vcursesconsole,
     {$ENDIF}
     vsdlio, vglconsole, vtig,
     vgl3library,
     doomtextures,  doombase,
     dfdata, dfoutput, dfplayer;

{ TDoomIO }

constructor TDoomIO.Create;
var iStyle      : TUIStyle;
    iCoreData   : TVDataFile;
    iImage      : TImage;
    iFontTexture: TTextureID;
    iFont       : TBitmapFont;
    iStream     : TStream;
    iFullscreen : Boolean;
    iCurrentWH  : TIOPoint;
    iDoQuery    : Boolean;
    iSDLFlags   : TSDLIOFlags;
    iMode       : TIODisplayMode;
  procedure ParseSettings( aFull : Boolean; const aPrefix : AnsiString; aDef : TIOPoint );
  begin
    with FSettings[ aFull ] do
    begin
      Width  := Config.Configure( aPrefix+'Width', aDef.X );
      Height := Config.Configure( aPrefix+'Height', aDef.Y );
      FMult  := Config.Configure( aPrefix+'FontMult', -1 );
      TMult  := Config.Configure( aPrefix+'TileMult', -1 );
      MiniM  := Config.Configure( aPrefix+'MiniMapSize', -1 );
      if Width  = -1 then Width  := iCurrentWH.X;
      if Height = -1 then Height := iCurrentWH.Y;
      if FMult  = -1 then
        if (Width >= 1600) and (Height >= 900)
          then FMult := 2
          else FMult := 1;
      if TMult  = -1 then
        if (Width >= 1050) and (Height >= 1050)
          then TMult := 2
          else TMult := 1;
      if MiniM = -1 then
      begin
        MiniM := Width div 220;
        MiniM := Max( 3, MiniM );
        MiniM := Min( 9, MiniM );
      end;
    end;
  end;

begin
  FTime := 0;
  FLastMouse := 0;
  FMouseLock := True;

  FAudio := TDoomAudio.Create;

  FLoading := nil;
  IO := Self;
  FVPadding := 0;
  FFontMult := 1;
  FTileMult := 1;
  FMCursor := nil;
  FQuadSheet := nil;
  FTextSheet := nil;
  FPostSheet := nil;
  Textures   := nil;
  FQuadRenderer := nil;

  if GraphicsVersion then
  begin
    {$IFDEF WINDOWS}
    if not GodMode then
    begin
      FreeConsole;
      vdebug.DebugWriteln := nil;
    end
    else
    begin
      Logger.AddSink( TConsoleLogSink.Create( LOGDEBUG, True ) );
    end;
    {$ENDIF}
    iFullScreen := Config.Configure( 'StartFullscreen', False ) or ForceFullscreen;
    {$IFDEF WINDOWS}
    iDoQuery := Config.Configure( 'FullscreenQuery', True );
    if iDoQuery then
      iFullScreen := MessageBox( 0, 'Do you want to run in fullscreen mode?'#10'You can toggle fullscreen any time by pressing Alt-Enter.'#10#10'You can also set the defaults in config.lua, to avoid this dialog.','DoomRL - Run fullscreen?', MB_YESNO or MB_ICONQUESTION ) = IDYES;
    {$ENDIF}

    if not TSDLIODriver.GetCurrentResolution( iCurrentWH ) then
      iCurrentWH.Init(800,600);

    ParseSettings( False, 'Windowed', vutil.Point(800,600) );
    ParseSettings( True, 'Fullscreen', vutil.Point(-1,-1) );

    with FSettings[ iFullscreen ] do
    begin
      iSDLFlags := [ SDLIO_OpenGL ];
      if iFullscreen then Include( iSDLFlags, SDLIO_Fullscreen );
      FIODriver := TSDLIODriver.Create( Width, Height, 32, iSDLFlags );
      FFontMult := FMult;
      FTileMult := TMult;
      FMiniScale:= MiniM;
    end;

    begin
      Log('Display modes (%d)', [FIODriver.DisplayModes.Size] );
      Log('-------');
      for iMode in FIODriver.DisplayModes do
        Log('%d x %d @%d', [ iMode.Width, iMode.Height, iMode.Refresh ] );
      Log('-------');
    end;

    Textures   := TDoomTextures.Create;

    if GodMode then
      iImage := LoadImage('font10x18.png')
    else
    begin
      iCoreData := TVDataFile.Create(DataPath+'doomrl.wad');
      iCoreData.DKKey := LoveLace;
      iStream := iCoreData.GetFile( 'font10x18.png', 'fonts' );
      iImage := LoadImage( iStream, iStream.Size );
      FreeAndNil( iStream );
      FreeAndNil( iCoreData );
    end;
    iFontTexture := Textures.AddImage( 'font10x18', iImage, Option_Blending );
    Textures[ iFontTexture ].Image.SubstituteColor( ColorBlack, ColorZero );
    Textures[ iFontTexture ].Upload;

    iFont := TBitmapFont.CreateFromGrid( iFontTexture, 32, 256-32, 32 );
    CalculateConsoleParams;
    FConsole := TGLConsoleRenderer.Create( iFont, 80, 25, FLineSpace, [VIO_CON_CURSOR] );
    TGLConsoleRenderer( FConsole ).SetPositionScale( (FIODriver.GetSizeX - 80*10*FFontMult) div 2, 0, FLineSpace, FFontMult );
    SpriteMap  := TDoomSpriteMap.Create;
    FQuadSheet := TGLQuadList.Create;
    FTextSheet := TGLQuadList.Create;
    FPostSheet := TGLQuadList.Create;
    FQuadRenderer := TGLQuadRenderer.Create;
    FMCursor      := TDoomMouseCursor.Create;
    TSDLIODriver( FIODriver ).ShowMouse( False );
  end
  else
  begin
    {$IFDEF WINDOWS}
    FIODriver := TTextIODriver.Create( 80, 25 );
    {$ELSE}
    FIODriver := TCursesIODriver.Create( 80, 25 );
    {$ENDIF}
    if (FIODriver.GetSizeX < 80) or (FIODriver.GetSizeY < 25) then
      raise EIOException.Create('Too small console available, resize your console to 80x25!');
    {$IFDEF WINDOWS}
    FConsole  := TTextConsoleRenderer.Create( 80, 25, [VIO_CON_BGCOLOR, VIO_CON_CURSOR] );
    {$ELSE}
    FConsole  := TCursesConsoleRenderer.Create( 80, 25, [VIO_CON_BGCOLOR, VIO_CON_CURSOR] );
    {$ENDIF}
  end;

  FIODriver.SetTitle('Doom, the Roguelike','DoomRL');

  iStyle := TUIStyle.Create('default');
  iStyle.Add('','fore_color', LightGray );
  iStyle.Add('','selected_color', Yellow );
  iStyle.Add('','inactive_color', DarkGray );
  iStyle.Add('','selinactive_color', Yellow );

  iStyle.Add('menu','fore_color', Red );
  iStyle.Add('plot_viewer','fore_color', Red );
  iStyle.Add('','back_color', Black );
  iStyle.Add('','scroll_chars', '^v' );
  iStyle.Add('','icon_color', White );
  iStyle.Add('','opaque', False );
  iStyle.Add('','frame_color', DarkGray );
  if (not Option_HighASCII) and ( not GraphicsVersion )
     then iStyle.Add('','frame_chars', '-|-|/\\/-|^v' )
     else iStyle.Add('','frame_chars', #196+#179+#196+#179+#218+#191+#192+#217+#196+#179+'^v' );
  iStyle.Add('window','fore_color', Red );
  iStyle.Add('','frame_color', Red );
  iStyle.Add('full_window','fore_color', LightRed );
  iStyle.Add('full_window','frame_color', Red );
  iStyle.Add('full_window','fore_color', LightRed );
  iStyle.Add('full_window','title_color', LightRed );
  iStyle.Add('full_window','footer_color', LightRed );
  iStyle.Add('input','fore_color', LightBlue );
  iStyle.Add('input','back_color', Blue );
  iStyle.Add('text','fore_color', LightGray );
  iStyle.Add('text','back_color', ColorNone );

  VTIG_Initialize( FConsole, FIODriver, False );

  inherited Create( FIODriver, FConsole, iStyle );
  LoadStart;

  UI := TDoomUI.Create;
  IO := Self;
  FConsole.Clear;
  FConsole.HideCursor;
  FLastTick := Now;
  FConsoleWindow := nil;
  FullUpdate;
end;

procedure TDoomIO.Configure ( aConfig : TLuaConfig; aReload : Boolean ) ;
begin

  aConfig.ResetCommands;
  aConfig.LoadKeybindings('Keybindings');
  // TODO : configurable
  if GodMode then
    RegisterDebugConsole( VKEY_F1 );
  FIODriver.RegisterInterrupt( VKEY_F9, @ScreenShotCallback );
  FIODriver.RegisterInterrupt( VKEY_F10, @BBScreenShotCallback );
  if GraphicsVersion then
  begin
    FIODriver.RegisterInterrupt( IOKeyCode( VKEY_ENTER, [ VKMOD_ALT ] ), @FullScreenCallback );
    FIODriver.RegisterInterrupt( IOKeyCode( VKEY_F12, [ VKMOD_CTRL ] ), @FullScreenCallback );
  end;

  if Option_MessageBuffer < 20 then Option_MessageBuffer := 20;

  FAudio.Configure( aConfig, aReload );

  if aReload then
    aConfig.EntryFeed('Colors', @ColorQuery );

end;

function TDoomIO.RunUILoop( aElement : TUIElement = nil ) : DWord;
begin
  if UI <> nil then UI.HudEnabled := False;
  if IO.MCursor <> nil then IO.MCursor.Active := True;
  FConsole.HideCursor;
  Result := inherited RunUILoop( aElement );
  if UI <> nil then UI.HudEnabled := True;
end;

procedure TDoomIO.FullUpdate;
begin
  VTIG_NewFrame;
  UI.OnRedraw;
  inherited FullUpdate;
end;

destructor TDoomIO.Destroy;
begin
  FreeAndNil( FMCursor );

  FreeAndNil( SpriteMap );
  FreeAndNil( Textures );
  FreeAndNil( FQuadSheet );
  FreeAndNil( FTextSheet );
  FreeAndNil( FPostSheet );
  FreeAndNil( FQuadRenderer );
  FreeAndNil( FAudio );
  IO := nil;
  inherited Destroy;
end;

procedure TDoomIO.Screenshot ( aBB : Boolean );
var iFName : AnsiString;
    iName  : AnsiString;
    iExt   : AnsiString;
    iCount : DWord;
    iCon   : TUIConsole;
begin
  if GraphicsVersion
     then iExt := '.png'
     else iExt := '.txt';

  iName := 'DoomRL';
  if Player <> nil then iName := Player.Name;
  iFName := 'screenshot'+PathDelim+ToProperFilename('['+FormatDateTime(Option_TimeStamp,Now)+'] '+iName)+iExt;
  iCount := 1;
  while FileExists(iFName) do
  begin
    iFName := 'screenshot'+PathDelim+ToProperFilename('['+FormatDateTime(Option_TimeStamp,Now)+'] '+iName)+'-'+IntToStr(iCount)+iExt;
    Inc(iCount);
  end;

  Log('Writing screenshot...: '+iFName);
  if not GraphicsVersion then
  begin
    iCon.Init( FConsole );
    if aBB then iCon.ScreenShot(iFName,1)
           else iCon.ScreenShot(iFName);
  end
  else
  begin
    TSDLIODriver(FIODriver).ScreenShot(iFName);
  end;
    {  if aBB then UI.Msg('BB Screenshot created.')
             else UI.Msg('Screenshot created.');}
end;

procedure TDoomIO.ColorQuery(nkey,nvalue : Variant);
begin
    ColorOverrides[nkey] := nvalue;
end;

function TDoomIO.FullScreenCallback ( aEvent : TIOEvent ) : Boolean;
var iFullscreen : Boolean;
    iSDLFlags   : TSDLIOFlags;
begin
  iFullscreen := TSDLIODriver(FIODriver).FullScreen;
  iFullscreen := not iFullscreen;
  with FSettings[ iFullscreen ] do
  begin
    iSDLFlags := [ SDLIO_OpenGL ];
    if not TSDLIODriver(FIODriver).FullScreen then Include( iSDLFlags, SDLIO_Fullscreen );
    TSDLIODriver(FIODriver).ResetVideoMode( Width, Height, 32, iSDLFlags );
    FTileMult := TMult;
    FFontMult := FMult;
    FMiniScale:= MiniM;
  end;
  ReuploadTextures;
  CalculateConsoleParams;
  TGLConsoleRenderer( FConsole ).SetPositionScale( (FIODriver.GetSizeX - 80*10*FFontMult) div 2, 0, FLineSpace, FFontMult );
  TGLConsoleRenderer( FConsole ).HideCursor;
  if (UI <> nil) then UI.SetMinimapScale(FMiniScale);
  FUIRoot.DeviceChanged;
  SpriteMap.Recalculate;
  if Player <> nil then
    SpriteMap.NewShift := SpriteMap.ShiftValue( Player.Position );
  Exit( True );
end;

function TDoomIO.ScreenShotCallback ( aEvent : TIOEvent ) : Boolean;
begin
  ScreenShot( False );
  Exit(True);
end;

function TDoomIO.BBScreenShotCallback ( aEvent : TIOEvent ) : Boolean;
begin
  ScreenShot( True );
  Exit(True);
end;

function TDoomIO.EventWaitForMore : Boolean;
begin
  if Option_MorePrompt then
  begin
    UI.SetHint('[more]');
    WaitForCommand([INPUT_OK,INPUT_MLEFT]);
    UI.SetHint('');
  end;
  UI.MsgUpdate;
  Exit( True );
end;

procedure TDoomIO.WADLoaded;
begin
  if GraphicsVersion then
  begin
    if IO.MCursor <> nil then MCursor.SetTextureID( Textures.TextureID['cursor'], 32 );
    FMsgFont := Lua.LoadFont( 'message' );
  end;
end;

procedure TDoomIO.LoadStart( aAdd : DWord = 0 );
begin
  if FLoading = nil then
  begin
    FLoading := TUILoadingScreen.Create(FUIRoot,100);
    FLoading.Max := FLoading.Max + aAdd;
  end;
end;

function TDoomIO.LoadCurrent : DWord;
begin
  if Assigned( FLoading ) then Exit( FLoading.Current );
  Exit( 0 );
end;

procedure TDoomIO.LoadProgress ( aProgress : DWord ) ;
begin
  if Assigned( FLoading ) then FLoading.OnProgress( aProgress );
  IO.FullUpdate;
end;

procedure TDoomIO.LoadStop;
begin
  FreeAndNil( FLoading );
end;

procedure TDoomIO.ReuploadTextures;
begin
  Textures.Upload;
  SpriteMap.ReassignTextures;
end;

procedure TDoomIO.CalculateConsoleParams;
begin
  FLineSpace := Max((FIODriver.GetSizeY - 25*18*FFontMult - 2*FVPadding) div 25 div FFontMult,0);
end;

procedure TDoomIO.Update( aMSec : DWord );
var iMousePos   : TUIPoint;

    iPoint   : TUIPoint;
    iValueX  : Single;
    iValueY  : Single;
    iActiveX : Integer;
    iActiveY : Integer;
    iMaxX    : Integer;
    iMaxY    : Integer;
    iShift   : TCoord2D;
begin
  FTime += aMSec;
  FAudio.Update( aMSec );
  if GraphicsVersion then
  begin
    if (Doom <> nil) and (UI <> nil) then UI.GFXAnimationUpdate( aMSec );
    if GraphicsVersion then GraphicsDraw;
    if FQuadRenderer <> nil then FQuadRenderer.Update( FProjection );
    if FQuadSheet <> nil then FQuadRenderer.Render( FQuadSheet );
  end;

  UI.OnUpdate( aMSec );

  if GraphicsVersion and (FMCursor.Active) and FIODriver.GetMousePos( iPoint ) and (not FMouseLock) then
  begin
    iMaxX   := FIODriver.GetSizeX;
    iMaxY   := FIODriver.GetSizeY;
    iValueX := 0;
    iValueY := 0;
    iActiveX := iMaxX div 8;
    iActiveY := iMaxY div 8;
    if iPoint.X < iActiveX       then iValueX := ((iActiveX -       iPoint.X) / iActiveX);
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
        Clamp( SpriteMap.Shift.X + Ceil( iValueX * aMSec ), SpriteMap.MinShift.X, SpriteMap.MaxShift.X ),
        Clamp( SpriteMap.Shift.Y + Ceil( iValueY * aMSec ), SpriteMap.MinShift.Y, SpriteMap.MaxShift.Y )
      );
      SpriteMap.NewShift := iShift;
      FMouseLock :=
        ((iShift.X = SpriteMap.MinShift.X) or (iShift.X = SpriteMap.MaxShift.X))
     and ((iShift.Y = SpriteMap.MinShift.Y) or (iShift.Y = SpriteMap.MaxShift.Y));
    end;
  end;

  FUIRoot.OnUpdate( aMSec );
  FUIRoot.Render;
  if FTextSheet <> nil then FQuadRenderer.Render( FTextSheet );

  VTIG_EndFrame;
  VTIG_Render;

  FConsole.Update;
  if (FPostSheet <> nil) and (FMCursor <> nil) and (FMCursor.Active) and FIODriver.GetMousePos(iMousePos) then
  begin
    FMCursor.Draw( iMousePos.X, iMousePos.Y, FLastUpdate, FPostSheet );
  end;
  if FPostSheet <> nil then FQuadRenderer.Render( FPostSheet );
end;

procedure TDoomIO.GraphicsDraw;
var iMeasure  : TDateTime;
    iTickTime : DWord;
    iSizeY    : DWord;
    iSizeX    : DWord;
begin
  iMeasure := Now;
  iTickTime := MilliSecondsBetween( iMeasure, FLastTick );
  FLastTick := iMeasure;

  iSizeY    := FIODriver.GetSizeY-2*FVPadding;
  iSizeX    := FIODriver.GetSizeX;
  glViewport( 0, FVPadding, iSizeX, iSizeY );

  glEnable( GL_TEXTURE_2D );
  glDisable( GL_DEPTH_TEST );
  glEnable( GL_BLEND );
  glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
  FProjection := GLCreateOrtho( 0, iSizeX, iSizeY, 0, -16384, 16384 );

  if (Doom <> nil) and (Doom.State = DSPlaying) then
  begin
    if FConsoleWindow = nil then
       FConsole.HideCursor;
    //if not UI.AnimationsRunning then SpriteMap.NewShift := SpriteMap.ShiftValue( Player.Position );
    SpriteMap.Update( iTickTime, FProjection );
    UI.GFXAnimationDraw;
    glEnable( GL_DEPTH_TEST );
    SpriteMap.Draw;
    glDisable( GL_DEPTH_TEST );
  end;
end;

procedure TDoomIO.WaitForEnter;
begin
  WaitForCommand([INPUT_OK,INPUT_MLEFT]);
end;

function TDoomIO.WaitForCommand ( const aSet : TCommandSet ) : Byte;
var iCommand : Byte;
    iEvent   : TIOEvent;
    iPoint   : TIOPoint;
begin
  repeat
    iCommand := 0;
    WaitForKeyEvent( iEvent, GraphicsVersion, GraphicsVersion and (INPUT_MMOVE in aSet) );
    if (iEvent.EType = VEVENT_SYSTEM) then
      if Option_LockClose
         then Exit( INPUT_QUIT )
         else Exit( INPUT_HARDQUIT );

    if (iEvent.EType = VEVENT_MOUSEMOVE) then
    begin
      iPoint := SpriteMap.DevicePointToCoord( iEvent.MouseMove.Pos );
      FMTarget.Create( iPoint.X, iPoint.Y );
      if Doom.Level.isProperCoord( FMTarget ) then
        Exit( INPUT_MMOVE );
    end;
    if iEvent.EType = VEVENT_MOUSEDOWN then
    begin
      iPoint := SpriteMap.DevicePointToCoord( iEvent.Mouse.Pos );
      FMTarget.Create( iPoint.X, iPoint.Y );
      if Doom.Level.isProperCoord( FMTarget ) then
      begin
        case iEvent.Mouse.Button of
          VMB_BUTTON_LEFT     : Exit( INPUT_MLEFT );
          VMB_BUTTON_MIDDLE   : Exit( INPUT_MMIDDLE );
          VMB_BUTTON_RIGHT    : Exit( INPUT_MRIGHT );
          VMB_WHEEL_UP        : Exit( INPUT_MSCRUP );
          VMB_WHEEL_DOWN      : Exit( INPUT_MSCRDOWN );
        end;
        if (aSet = []) then Exit(iCommand);
      end;
    end
    else
    begin
      FKeyCode := IOKeyEventToIOKeyCode( iEvent.Key );
      iCommand := Config.Commands[ FKeyCode ];
      if (aSet = []) and ((FKeyCode mod 256) <> 0) then Exit( iCommand );
    end;
  until (iCommand in aSet);
  Exit( iCommand )
end;

function TDoomIO.WaitForKey ( const aSet : TKeySet ) : Byte;
var iKey   : Byte;
    iEvent : TIOEvent;
begin
  repeat
    WaitForKeyEvent( iEvent );
    if (iEvent.EType = VEVENT_SYSTEM) and (iEvent.System.Code = VIO_SYSEVENT_QUIT) then Exit( 1 );
    iKey := Ord( iEvent.Key.ASCII );
    if iEvent.Key.Code = vioevent.VKEY_ESCAPE then iKey := 1; // TODO: temp! remove!
    if aSet = [] then Exit( iKey );
  until iKey in aSet;
  Exit( iKey );
end;

procedure TDoomIO.WaitForKeyEvent ( out aEvent : TIOEvent;
  aMouseClick : Boolean; aMouseMove : Boolean );
var iEndLoop : TIOEventTypeSet;
    iPeek    : TIOEvent;
    iResult  : Boolean;
begin
  iEndLoop := [VEVENT_KEYDOWN];
  if aMouseClick then Include( iEndLoop, VEVENT_MOUSEDOWN );
  if aMouseMove  then Include( iEndLoop, VEVENT_MOUSEMOVE );
  repeat
    while not FIODriver.EventPending do
    begin
      FullUpdate;
      FIODriver.Sleep(10);
    end;
    if not FIODriver.PollEvent( aEvent ) then continue;
    if ( aEvent.EType = VEVENT_MOUSEMOVE ) and FIODriver.EventPending then
    begin
      repeat
        iResult := FIODriver.PeekEvent( iPeek );
        if ( not iResult ) or ( iPeek.EType <> VEVENT_MOUSEMOVE ) then break;
        FIODriver.PollEvent( aEvent );
      until (not FIODriver.EventPending);
    end;
    if OnEvent( aEvent ) or FUIRoot.OnEvent( aEvent ) then aEvent.EType := VEVENT_KEYUP;
    if (aEvent.EType = VEVENT_SYSTEM) and (aEvent.System.Code = VIO_SYSEVENT_QUIT) then
      Exit;
  until aEvent.EType in iEndLoop;
end;

function TDoomIO.CommandEventPending : Boolean;
var iEvent : TIOEvent;
begin
  repeat
    if not FIODriver.PeekEvent( iEvent ) then Exit( False );
    if iEvent.EType in [ VEVENT_MOUSEMOVE, VEVENT_MOUSEUP ] then
    begin
      FIODriver.PollEvent( iEvent );
      Continue;
    end;
  until True;
  Exit( iEvent.EType in [ VEVENT_KEYDOWN, VEVENT_MOUSEDOWN ] );
end;

function TDoomIO.OnEvent( const event : TIOEvent ) : Boolean;
begin
  if event.EType in [ VEVENT_MOUSEMOVE, VEVENT_MOUSEDOWN ] then
  begin
    if FMCursor <> nil then FMCursor.Active := True;
    FLastMouse := FTime;
    FMouseLock := False;
  end;
  Exit( False )
end;

procedure EmitCrashInfo ( const aInfo : AnsiString; aInGame : Boolean ) ;
function Iff(expr : Boolean; const str : AnsiString) : AnsiString;
begin
  if expr then exit(str) else exit('');
end;
var iErrorMessage : AnsiString;
begin
  {$IFDEF WINDOWS}
  if GraphicsVersion then
  begin
    iErrorMessage := 'DoomRL crashed!'#10#10'Reason : '+aInfo+#10#10
     +'If this reason doesn''t seem your fault, please submit a bug report at http://forum.chaosforge.org/'#10
     +'Be sure to include the last entries in your error.log that will get created once you hit OK.'
     +Iff(aInGame and Option_SaveOnCrash,#10'DoomRL will also attempt to save your game, so you may continue on the next level.');
    MessageBox( 0, PChar(iErrorMessage),
     'DoomRL - Fatal Error!', MB_OK or MB_ICONERROR );
  end
  else
  {$ENDIF}
  begin
    DoneVideo;
    Writeln;
    Writeln;
    Writeln;
    Writeln('Abnormal program termination!');
    Writeln;
    Writeln('Reason : ',aInfo);
    Writeln;
    Writeln('If this reason doesn''t seem your fault, please submit a bug report at' );
    Writeln('http://forum.chaosforge.org/, be sure to include the last entries in');
    Writeln('your error.log that will get created once you hit Enter.');
    if aInGame and Option_SaveOnCrash then
    begin
      Writeln( 'DoomRL will also attempt to save your game, so you may continue on' );
      Writeln( 'the next level.' );
    end;
    Readln;
  end;
end;


end.


{$INCLUDE doomrl.inc}
unit doommainmenuview;
interface
uses vgenerics, vtextures, dfdata, doomio;

type TMainMenuViewMode = (
  MAINMENU_FIRST, MAINMENU_INTRO, MAINMENU_MENU,
  MAINMENU_DIFFICULTY, MAINMENU_FAIR, MAINMENU_KLASS, MAINMENU_TRAIT, MAINMENU_NAME,
  MAINMENU_BADSAVE, MAINMENU_DONE );

type TMainMenuEntry = record
  Name  : Ansistring;
  Desc  : Ansistring;
  Allow : Boolean;
  ID    : Ansistring;
  NID   : Byte;
end;

type TMainMenuEntryArray = specialize TGArray< TMainMenuEntry >;

type TMainMenuView = class( TInterfaceLayer )
  constructor Create( aInitial : TMainMenuViewMode = MAINMENU_FIRST; aResult : TMenuResult = nil );
  procedure Update( aDTime : Integer ); override;
  function IsFinished : Boolean; override;
  function IsModal : Boolean; override;
  destructor Destroy; override;
protected
  procedure Render;
  procedure UpdateFirst;
  procedure UpdateIntro;
  procedure UpdateMenu;
  procedure UpdateBadSave;
  procedure UpdateFair;
  procedure UpdateDifficulty;
  procedure OnCancel;
  procedure SetSoundCallback;
  procedure ResetSoundCallback;
  procedure ReloadArrays;
protected
  FMode        : TMainMenuViewMode;
  FFirst       : Ansistring;
  FIntro       : Ansistring;
  FResult      : TMenuResult;
  FSaveExists  : Boolean;

  FArrayCType  : TMainMEnuEntryArray;
  FArrayDiff   : TMainMEnuEntryArray;
  FArrayKlass  : TMainMEnuEntryArray;

  FBGTexture   : TTextureID;
  FLogoTexture : TTextureID;
end;

implementation

uses {$IFDEF WINDOWS}Windows,{$ELSE}Unix,{$ENDIF}
     math, sysutils,
     vutil, vtig, vtigio, vimage, vgltypes, vluasystem, vsound,
     dfhof,
     doombase, doomgfxio, doomplayerview, doomhelpview, doomsettingsview, doompagedview, doomchallengesview;

const MAINMENU_ID = 'mainmenu';

var ChallengeType : array[1..4] of TMainMenuEntry =
((
   Name : 'Angel Game';
   Desc : 'Play one of the DRL classic challenge games that place restrictions on play style or modify play behaviour.'#10#10'Reach @yPrivate FC@> rank to unlock!';
   Allow : True; ID : ''; NID : 0;
),(
   Name : 'Dual-angel Game';
   Desc : 'Mix two DRL challenge game types. Only the first counts highscore-wise - the latter is your own challenge!'#10#10'Reach @ySergeant@> rank to unlock!';
   Allow : True; ID : ''; NID : 0;
),(
   Name : 'Archangel Game';
   Desc : 'Play one of the DRL challenge in its ultra hard form. Do not expect fairness here!'#10#10'Reach @ySergeant@> rank to unlock!';
   Allow : True; ID : ''; NID : 0;
),(
   Name : 'Custom Challenge';
   Desc : 'Play one of many custom DRL challenge levels and episodes. Download new ones from the @yCustom game/Download Mods@> option in the main menu.';
   Allow : True; ID : ''; NID : 0;
));


constructor TMainMenuView.Create( aInitial : TMainMenuViewMode = MAINMENU_FIRST; aResult : TMenuResult = nil );
var iText : Text;
begin
  VTIG_EventClear;
  VTIG_ResetSelect( MAINMENU_ID );

  FMode       := aInitial;
  FResult     := aResult;
  FSaveExists := False;
  FArrayCType := nil;
  FArrayDiff  := nil;
  FArrayKlass := nil;

  if not ( FMode in [MAINMENU_FIRST,MAINMENU_INTRO] ) then
    Assert( aResult <> nil, 'nil result passed!' );

  if FMode = MAINMENU_FIRST then
  begin
    if not FileExists( WritePath + 'drl.prc' ) then
    begin
      Assign(iText, WritePath + 'drl.prc');
      Rewrite(iText);
      Writeln(iText,'DRL{$IFDEF WINDOWS}Windows,{$ELSE}Unix,{$ENDIF} was already run.');
      Close(iText);

      FFirst := AnsiString( LuaSystem.ProtectedCall( ['DoomRL','first_text'], [] ) );
    end
    else
      FMode := MAINMENU_INTRO;
  end;

  if FMode in [MAINMENU_FIRST,MAINMENU_INTRO] then
    FIntro := AnsiString( LuaSystem.ProtectedCall( ['DoomRL','logo_text'], [] ) );

  if GraphicsVersion then
  begin
    FBGTexture   := (IO as TDoomGFXIO).Textures.TextureID['background'];
    FLogoTexture := (IO as TDoomGFXIO).Textures.TextureID['logo'];
  end;

  if FMode = MAINMENU_MENU then
  begin
    FSaveExists := Doom.SaveExists;
  end;
end;

procedure TMainMenuView.Update( aDTime : Integer );
begin
  VTIG_Clear;
  if GraphicsVersion then Render;
  if not IO.IsTopLayer( Self ) then
  begin
    ResetSoundCallback;
    Exit;
  end;
  SetSoundCallback;

  case FMode of
    MAINMENU_FIRST      : UpdateFirst;
    MAINMENU_INTRO      : UpdateIntro;
    MAINMENU_MENU       : UpdateMenu;
    MAINMENU_BADSAVE    : UpdateBadSave;
    MAINMENU_DIFFICULTY : UpdateDifficulty;
    MAINMENU_FAIR       : UpdateFair;
  end;
end;

procedure TMainMenuView.UpdateFirst;
begin
  VTIG_FreeLabel( FFirst, Rectangle(5,2,70,23) );
  if VTIG_EventCancel or VTIG_EventConfirm then
    FMode := MAINMENU_INTRO;
end;

procedure TMainMenuView.UpdateIntro;
var iCount  : Integer;
    iString : AnsiString;
begin
  if not GraphicsVersion then
    if IO.Ascii.Exists('logo') then
    begin
      iCount := 0;
      for iString in IO.Ascii['logo'] do
      begin
        VTIG_FreeLabel( iString, Point( 17, iCount ) );
        Inc( iCount );
      end;
    end;

  VTIG_FreeLabel( '{rDRL version {R'+VERSION_STRING+'}}', Point( 28, 9 ) );
  VTIG_FreeLabel( '{rby {RKornel Kisielewicz}}', Point( 28, 10 ) );
  VTIG_FreeLabel( '{rgraphics by {RDerek Yu}}', Point( 28, 11 ) );
  VTIG_FreeLabel( '{rand {RLukasz Sliwinski}}', Point( 28, 12 ) );

  VTIG_FreeLabel( FIntro, Rectangle(2,14,77,11) );

  if VTIG_EventCancel or VTIG_EventConfirm then
    FMode := MAINMENU_DONE;
end;

const
  TextContinueGame  = '{b--} Continue game {b---}';
  TextNewGame       = '{b-----} New game {b-----}';
  TextChallengeGame = '{b--} Challenge game {b--}';
  TextJHC           = '{B==} Wishlist JHC! {B===}';
  TextShowHighscore = '{b-} Show highscores {b--}';
  TextShowPlayer    = '{b---} Show player {b----}';
  TextExit          = '{b------} Exit {b--------}';
  TextHelp          = '{b------} Help {b--------}';
  TextSettings      = '{b----} Settings {b------}';

const
  JHCURL = 'http://jupiterhellclassic.com/';

procedure TMainMenuView.UpdateMenu;
begin
  VTIG_PushStyle( @TIGStyleFrameless );
  VTIG_Begin( 'mainmenu', Point( 24, 9 ), Point( 29, 14 ) );
  VTIG_PopStyle;
    VTIG_PushStyle( @TIGStyleColored );
    if FSaveExists then
      if VTIG_Selectable( TextContinueGame ) then
      begin
        if Doom.LoadSaveFile then
        begin
          FResult.Loaded := True;
          FMode := MAINMENU_DONE;
        end
        else
          FMode := MAINMENU_BADSAVE;
      end;
    if not FSaveExists then
      if VTIG_Selectable( TextNewGame ) then
      begin
        ReloadArrays;
        FResult.Challenge := '';
        FMode := MAINMENU_DIFFICULTY;
      end;
    if VTIG_Selectable( TextChallengeGame, (not FSaveExists) ) then
    begin
      ReloadArrays;
      FMode := MAINMENU_DONE;
    end;
    if VTIG_Selectable( TextShowHighscore ) then IO.PushLayer( TPagedView.Create( HOF.GetPagedScoreReport ) );
    if VTIG_Selectable( TextShowPlayer )    then IO.PushLayer( TPagedView.Create( HOF.GetPagedPlayerReport ) );
    if VTIG_Selectable( TextHelp )          then IO.PushLayer( THelpView.Create );
    if VTIG_Selectable( TextSettings )      then IO.PushLayer( TSettingsView.Create );
    if VTIG_Selectable( TextJHC ) then
    begin
      {$IFDEF UNIX}
      fpSystem('xdg-open ' + JHCURL); // Unix-based systems
      {$ENDIF}
      {$IFDEF WINDOWS}
        ShellExecute(0, 'open', PChar(JHCURL), nil, nil, SW_SHOWNORMAL); // Windows
      {$ENDIF}
    end;
    if VTIG_Selectable( TextExit ) then
    begin
      FResult.Quit := True;
      FMode := MAINMENU_DONE;
    end;
    VTIG_PopStyle;
  VTIG_End;

  VTIG_FreeLabel('{BSupport the game by {Lwishlisting} the DRL expansion at {Ljupiterhellclassic.com}!}', Point(2,24) );


  if VTIG_EventCancel then
  begin
    OnCancel;
    if VTIG_Selected( MAINMENU_ID ) = 7
      then FMode := MAINMENU_DONE
      else VTIG_ResetSelect( MAINMENU_ID, 7 );
  end;
end;

procedure TMainMenuView.UpdateBadSave;
begin
  VTIG_BeginWindow('Corrupted save file', Point( 42, 8 ), Point(19,8) );
  VTIG_Text('Save file is corrupted! Removed corrupted save file, sorry :(.');
  VTIG_End('Press <{!Enter,Escape}> to continue...');
  IO.RenderUIBackground( Point(18,7), Point(60,15), 0.7 );
  if VTIG_EventCancel or VTIG_EventConfirm then
    FMode := MAINMENU_MENU;
end;

procedure TMainMenuView.UpdateFair;
begin
  VTIG_BeginWindow('Warning', Point( 40, 9 ), Point(21,14) );
  VTIG_PushStyle( @TIGStyleColored );
  VTIG_Text('Are you sure? This difficulty level isn''t even remotely fair!');
  VTIG_Text('');

  if VTIG_Selectable( 'Bring it on!' ) then
    FMode := MAINMENU_MENU;
  if VTIG_Selectable( 'Cancel' ) then
    FMode := MAINMENU_DIFFICULTY;
  VTIG_PopStyle;
  VTIG_End();
  IO.RenderUIBackground( Point(20,13), Point(60,22), 0.7 );
  if VTIG_EventCancel then
  begin
    OnCancel;
    FMode := MAINMENU_DIFFICULTY;
  end;
end;

procedure TMainMenuView.UpdateDifficulty;
var i : Integer;
begin
  VTIG_PushStyle( @TIGStyleFrameless );
  VTIG_Begin( 'mainmenu_difficulty', Point( 26, 9 ), Point( 29, 16 ) );
  VTIG_PopStyle;
    VTIG_PushStyle( @TIGStyleColored );
    for i := 0 to FArrayDiff.Size - 1 do
      if VTIG_Selectable( FArrayDiff[i].Name, FArrayDiff[i].Allow ) then
      begin
        FResult.Difficulty := FArrayDiff[i].NID;
        if FResult.Difficulty >= 5
          then FMode := MAINMENU_FAIR
          else FMode := MAINMENU_MENU;
      end;
    VTIG_PopStyle;
  VTIG_End;

  IO.RenderUIBackground( Point(23,15), Point(57,22), 0.7 );
  if VTIG_EventCancel then
  begin
    FMode := MAINMENU_MENU;
    OnCancel;
  end;
end;


procedure TMainMenuView.OnCancel;
begin
  if (not Option_Sound) or (Sound = nil) or ( not Setting_MenuSound ) then Exit;
  Sound.PlaySample('menu.cancel');
end;

procedure SoundCallback( aEvent : TTIGSoundEvent; aParam : Pointer );
begin
  if (not Option_Sound) or (Sound = nil) or ( not Setting_MenuSound ) then Exit;
  case aEvent of
    VTIG_SOUND_CHANGE : Sound.PlaySample('menu.change');
    VTIG_SOUND_ACCEPT : Sound.PlaySample('menu.pick');
  end;
end;

procedure TMainMenuView.SetSoundCallback;
begin
  VTIG_GetIOState.SoundCallback := @SoundCallback;
end;

procedure TMainMenuView.ResetSoundCallback;
begin
  VTIG_GetIOState.SoundCallback := nil;
end;


procedure TMainMenuView.Render;
var iIO             : TDoomGFXIO;
    iMin, iMax      : TGLVec2f;
    iSize, iSz, iTC : TGLVec2f;
    iImage          : TImage;
begin
  iIO := IO as TDoomGFXIO;
  Assert( iIO <> nil );

  iImage := iIO.Textures.Texture[ FBGTexture ].Image;
  iTC.Init( iImage.RawX / iImage.SizeX, iImage.RawY / iImage.SizeY );
  iSize.Init( IO.Driver.GetSizeX, IO.Driver.GetSizeY );
  iMin.Init( 0,0 );
  iMax := iSize - GLVec2f( 1, 1 );

  if (iImage.RawX / iImage.RawY) > (iSize.X / iSize.Y) then
  begin
    iSz.X  := iImage.RawX * (IO.Driver.GetSizeY / iImage.RawY);
    iMin.X := ( IO.Driver.GetSizeX - iSz.X ) / 2;
    iMax.X := iMin.X + iSz.X;
  end
  else
  begin
    iSz.Y  := iImage.RawY * (IO.Driver.GetSizeX / iImage.RawX);
    iMin.Y := ( IO.Driver.GetSizeY - iSz.Y ) / 2;
    iMax.Y := iMin.Y + iSz.Y;
  end;

  iIO.QuadSheet.PushTexturedQuad(
    GLVec2i(Floor(iMin.X), Floor(iMin.Y)),
    GLVec2i(Floor(iMax.X), Floor(iMax.Y)),
    GLVec2f(0,0),iTC,
    iIO.Textures.Texture[ FBGTexture ].GLTexture
  );

  if FMode = MAINMENU_FIRST then
    IO.RenderUIBackground( Point(4,1), Point(76,24), 0.7 );

  if ( FMode in [MAINMENU_INTRO,MAINMENU_MENU,MAINMENU_DIFFICULTY,MAINMENU_FAIR] ) and IO.IsTopLayer( Self ) then
  begin
    iImage := iIO.Textures.Texture[ FLogoTexture ].Image;
    iMin.Y  := Floor(iSize.Y / 25) * (-8);
    if (FMode <> MAINMENU_INTRO)
      then begin iMax.Y  := Floor(iSize.Y / 25) * 24; iMin.Y := Floor(iSize.Y / 25) * (-10); end
      else iMax.Y  := Floor(iSize.Y / 25) * 18;
    iMin.X  := (iSize.X - (iMax.Y - iMin.Y)) / 2;
    iMax.X  := (iSize.X + (iMax.Y - iMin.Y)) / 2;

    iIO.QuadSheet.PushTexturedQuad(
      GLVec2i(Floor(iMin.X), Floor(iMin.Y)),
      GLVec2i(Floor(iMax.X), Floor(iMax.Y)),
      GLVec2f( 0,0 ), GLVec2f( 1,1 ),
      iIO.Textures.Texture[ FLogoTexture ].GLTexture
    );

    case FMode of
      MAINMENU_INTRO : begin
        IO.RenderUIBackground( Point(25,9), Point(55,13), 0.7 );
        IO.RenderUIBackground( Point(1,14), Point(79,25), 0.7 );
      end;
      MAINMENU_MENU : begin
        IO.RenderUIBackground( Point(23,13), Point(57,23), 0.7 );
        IO.RenderUIBackground( Point(0,24),  Point(80,25), 0.7 );
      end;
    end;

  end;

end;


function TMainMenuView.IsFinished : Boolean;
begin
  Exit( FMode = MAINMENU_DONE );
end;

function TMainMenuView.IsModal : Boolean;
begin
  Exit( True );
end;

procedure TMainMenuView.ReloadArrays;
var iEntry : TMainMenuEntry;
    iTable : TLuaTable;
    iCount : Word;
begin
  if FArrayCType = nil then FArrayCType := TMainMEnuEntryArray.Create;
  if FArrayDiff  = nil then FArrayDiff  := TMainMEnuEntryArray.Create;
  if FArrayKlass = nil then FArrayKlass := TMainMEnuEntryArray.Create;
  FArrayCType.Clear;
  FArrayDiff.Clear;
  FArrayKlass.Clear;

  ChallengeType[1].Allow := (HOF.SkillRank > 0) or (GodMode) or (Setting_UnlockAll);
  ChallengeType[2].Allow := (HOF.SkillRank > 3) or (GodMode) or (Setting_UnlockAll);
  ChallengeType[3].Allow := (HOF.SkillRank > 3) or (GodMode) or (Setting_UnlockAll);
  FArrayCType.Push( ChallengeType[1] );
  FArrayCType.Push( ChallengeType[2] );
  FArrayCType.Push( ChallengeType[3] );

  for iTable in LuaSystem.ITables('diff') do
  with iTable do
  begin
    FillChar( iEntry, Sizeof(iEntry), 0 );
    iEntry.Allow := True;
    if (FResult.Challenge <> '') and (not GetBoolean( 'challenge' )) then iEntry.Allow := False;
    if GetInteger('req_skill',0) > HOF.SkillRank then iEntry.Allow := Setting_UnlockAll;
    if GetInteger('req_exp',0)   > HOF.ExpRank   then iEntry.Allow := Setting_UnlockAll;
    iEntry.Name := GetString('name');
    iEntry.Desc := '';
    iEntry.ID   := GetString('id');
    iEntry.NID  := GetInteger('nid');
    FArrayDiff.Push( iEntry );
  end;

  for iCount := 1 to LuaSystem.Get(['klasses','__counter']) do
    with LuaSystem.GetTable([ 'klasses', iCount ]) do
    try
      if not GetBoolean( 'hidden',False ) then
      begin
        iEntry.Name  := GetString('name');
        iEntry.Desc  := GetString('desc');
        iEntry.ID    := GetString('id');
        iEntry.NID   := GetInteger('nid');
        iEntry.Allow := True;
      end;
    finally
      Free;
    end;

end;

destructor TMainMenuView.Destroy;
begin
  FreeAndNil( FArrayCType );
  FreeAndNil( FArrayDiff );
  FreeAndNil( FArrayKlass );
  ResetSoundCallback;
  inherited Destroy;
end;

end.


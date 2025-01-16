{$INCLUDE doomrl.inc}
unit doomanimation;

interface

uses
  Classes, SysUtils, math,
  vnode, vutil, vcolor, vmath, vvector, vrltools, vvision, vanimation,
  dfdata;

type TAnimation        = vanimation.TAnimation;
     TAnimationManager = vanimation.TAnimations;

{ TDoomMissile }

TDoomMissile = class(TAnimation)
  constructor Create( aDuration : DWord; aDelay : DWord; aSource, aTarget : TCoord2D; aDrawDelay : Word; aSprite : TSprite; aRay : Boolean = False );
  procedure OnUpdate( aTime : DWord ); override;
  procedure OnDraw; override;
private
  FSource   : TVec2i;
  FTarget   : TVec2i;
  FPath     : TVisionRay;
  FHeading  : Float;
  FRay      : Boolean;
  FSprite   : TSprite;
  FStepDelay: DWord;
  FStep     : Word;
end;

{ TDoomMessage }

{TDoomMessage = class(TAnimation)
  constructor Create( aMessage : Ansistring );
  procedure OnDraw; override;
private
  FMessage : AnsiString;
end;}

{ TDoomMark }

TDoomMark = class(TAnimation)
  constructor Create( aDuration : DWord; aDelay : DWord; aCoord : TCoord2D );
  procedure OnDraw; override;
private
  FCoord : TCoord2D;
end;

{ TDoomExplodeMark }

TDoomExplodeMark = class(TAnimation)
  constructor Create( aDuration : DWord; aDelay : DWord; aCoord : TCoord2D; aColor : Byte );
  procedure OnDraw; override;
private
  FCoord    : TCoord2D;
  FGColor1  : TColor;
  FGColor2  : TColor;
  FGColor3  : TColor;
end;

{ TDoomSoundEvent }

TDoomSoundEvent = class(TAnimation)
  constructor Create( aDelay : DWord; aPosition : TCoord2D; aSoundID : DWord );
  procedure OnStart; override;
private
  FPosition : TCoord2D;
  FSoundID  : DWord;
end;

{ TDoomBlink }

TDoomBlink = class(TAnimation)
  constructor Create( aDuration : DWord; aDelay : DWord; aColor : Word );
  procedure OnDraw; override;
private
  FGColor   : TColor;
end;

{ TDoomMove }

TDoomMove = class(TAnimation)
  constructor Create( aDuration : DWord; aDelay : DWord; aUID : TUID; aFrom, aTo : TCoord2D; aSprite : TSprite; aPartial : Single = 0.0 );
  procedure OnStart; override;
  procedure OnDraw; override;
  destructor Destroy; override;
private
  FLightStart : Byte;
  FLightEnd   : Byte;
  FSprite     : TSprite;
  FPosition   : TVec2i;
  FSource     : TVec2i;
  FTarget     : TVec2i;
public
  property LastPosition : TVec2i read FPosition;
end;

{ TDoomScreenMove }

TDoomScreenMove = class(TAnimation)
  constructor Create( aDuration : DWord; aTo : TCoord2D );
  class function Update( aDuration : DWord; aTo : TCoord2D ) : Boolean;
  procedure OnUpdate( aTime : DWord ); override;
  procedure OnDraw; override;
  destructor Destroy; override;
private
  FSource : TVec2i;
  FDest   : TVec2i;
protected
  class var CCurrent : TDoomScreenMove;
end;


TDoomAnimateCell = class(TAnimation)
  constructor Create( aDuration : DWord; aDelay : DWord; aCoord : TCoord2D; aSprite : TSprite; aValue : Integer );
  procedure OnStart; override;
  procedure OnDraw; override;
  destructor Destroy; override;
private
  FSprite : TSprite;
  FCoord  : TCoord2D;
  FValue  : Integer;
end;

{ TDoomScreenShake }

TDoomScreenShake = class(TAnimation)
  constructor Create( aDuration : DWord; aDelay : DWord; aStrength : Single );
  class function Update( aDuration : DWord; aDelay : DWord; aStrength : Single ) : Boolean;
  procedure OnUpdate( aTime : DWord ); override;
  procedure OnDraw; override;
  destructor Destroy; override;
private
  FStrength   : Single;
  FFrequencyX : Single;
  FFrequencyY : Single;
protected
  class var CCurrent : TDoomScreenShake;
end;


implementation

uses viotypes, vuid, vlog, vdebug,
     dfbeing,
     doombase, doomgfxio, doomio, doomspritemap;

{ TDoomMissile }

constructor TDoomMissile.Create(aDuration : DWord; aDelay : DWord; aSource, aTarget: TCoord2D; aDrawDelay: Word; aSprite : TSprite;
  aRay: Boolean);
var iSize : Word;
begin
  inherited Create( aDuration, aDelay, 0 );
  FPath.Init(Doom.Level,aSource,aTarget);
  FSprite := aSprite;
  FStepDelay := Max( FDuration div Max( ( aSource - aTarget ).LargerLength, 1 ), 1 );
  FRay    := aRay;
  FStep   := 0;
  FPath.Next;
  FPath.Prev := aSource;
  iSize := SpriteMap.GetGridSize;

  FSource.Init( aSource.X*iSize-iSize div 2, aSource.Y*iSize-iSize div 2 );
  FTarget.Init( aTarget.X*iSize-iSize div 2, aTarget.Y*iSize-iSize div 2 );
  FHeading := -arctan2( aTarget.X - aSource.X, aTarget.Y - aSource.Y );
  if FHeading < 0 then FHeading := FHeading + 2*PI;
end;

procedure TDoomMissile.OnUpdate( aTime : DWord );
var iOldStep : Word;
begin
  inherited OnUpdate( aTime );
  iOldStep := FStep;
  if not FRay then
  begin
    FStep    := FTime div FStepDelay;
    if FStep > iOldStep then
    for iOldStep := iOldStep+1 to FStep do
    begin
      FPath.Next;
      if FPath.Done then Break;
    end;
  end;
end;

procedure TDoomMissile.OnDraw;
var iPos : TVec2i;
begin
  if Doom.Level.isProperCoord( FPath.GetC ) and Doom.Level.isVisible( FPath.GetC ) then
  begin
    iPos := Lerp( FSource, FTarget, Minf(FTime / FDuration, 1.0) );
    SpriteMap.PushSpriteFXRotated( iPos, FSprite, FHeading + PI/2)
  end;
end;

{ TDoomMessage }

{constructor TDoomMessage.Create(aMessage: Ansistring);
begin
  inherited Create;
  FMessage := aMessage;
end;

procedure TDoomMessage.Draw;
begin
  if (not FExpired) and (not UI.isMsgWaiting) then ;
  begin
    UI.Msg(FMessage);
    FExpired := True;
  end;
end;}

{ TDoomMark }

constructor TDoomMark.Create( aDuration : DWord; aDelay : DWord; aCoord : TCoord2D );
begin
  inherited Create( aDuration, aDelay, 0 );
  FCoord    := aCoord;
end;

procedure TDoomMark.OnDraw;
var iMarkSprite : TSprite;
begin
  iMarkSprite.Flags       := [];
  iMarkSprite.SpriteID[0] := HARDSPRITE_HIT;
  SpriteMap.PushSpriteFX( FCoord, iMarkSprite )
end;

{ TDoomExplodeMark }

constructor TDoomExplodeMark.Create( aDuration : DWord; aDelay : DWord; aCoord: TCoord2D; aColor: Byte );
var c1, c2, c3 : Byte;
begin
  inherited Create( Max( aDuration, 1 ), aDelay, 0 );
  case aColor of
    LightBlue: begin C1 := LightBlue;C2 := Cyan;       C3 := LightBlue;  end;
    Blue     : begin C1 := Blue;     C2 := LightBlue;  C3 := LightBlue;  end;
    Magenta  : begin C1 := Magenta;  C2 := Red;        C3 := Blue;   end;
    Green    : begin C1 := Green;    C2 := LightGreen; C3 := LightGreen;  end;
    LightRed : begin C1 := LightRed; C2 := Yellow;     C3 := White;  end;
    Yellow   : begin C1 := Brown;    C2 := Yellow;     C3 := White;  end;
  else         begin C1 := Red;      C2 := LightRed;   C3 := Yellow; end;
  end;
  FGColor1 := vcolor.NewColor(c1);
  FGColor2 := vcolor.NewColor(c2);
  FGColor3 := vcolor.NewColor(c3);
  FCoord    := aCoord;
end;

procedure TDoomExplodeMark.OnDraw;
var iMarkSprite : TSprite;
begin
  iMarkSprite.Flags       := [ SF_OVERLAY ];
  iMarkSprite.SpriteID[0] := HARDSPRITE_EXPL;

  case (( FTime * 3 ) div FDuration) of
    0 : iMarkSprite.Color    := FGColor1;
    1 : iMarkSprite.Color    := FGColor2;
    2 : iMarkSprite.Color    := FGColor3;
  else iMarkSprite.Color    := FGColor2;
  end;
  SpriteMap.PushSpriteFX( FCoord, iMarkSprite );
end;

{ TDoomSoundEvent }

constructor TDoomSoundEvent.Create( aDelay : DWord; aPosition : TCoord2D; aSoundID : DWord );
begin
  inherited Create( 1, aDelay, 0 );
  FPosition := aPosition;
  FSoundID  := aSoundID;
end;

procedure TDoomSoundEvent.OnStart;
begin
  IO.Audio.PlaySound( FSoundID, FPosition );
end;

{ TDoomBlink }

constructor TDoomBlink.Create( aDuration : DWord; aDelay : DWord; aColor: Word );
begin
  inherited Create( aDuration, aDelay, 0 );
  FGColor   := NewColor( aColor );
end;

procedure TDoomBlink.OnDraw;
begin
  if GraphicsVersion then
    (IO as TDoomGFXIO).PostSheet.PushColoredQuad( TVec2i.Create(0,0), TVec2i.Create(IO.Driver.GetSizeX,IO.Driver.GetSizeY), TVec4f.Create(FGColor.R,FGColor.G,FGColor.B,0.7) );
end;

{ TDoomMove }

constructor TDoomMove.Create ( aDuration : DWord; aDelay : DWord; aUID : TUID; aFrom, aTo : TCoord2D;
  aSprite : TSprite; aPartial : Single ) ;
var iSize : Word;
begin
  inherited Create( aDuration, aDelay, 0 );
  FUID        := aUID;
  FSprite     := aSprite;
  FLightStart := Iif( Doom.Level.isVisible(aFrom), 255, 0 );
  FLightEnd   := Iif( Doom.Level.isVisible(aTo),   255, 0 );

  if Doom.Level.Flags[ LF_BEINGSVISIBLE ] then
  begin
    FLightStart := Max( FLightStart, 40 );
    FLightEnd   := Max( FLightEnd, 40 );
  end;

  iSize := SpriteMap.GetGridSize;
  FSource.Init( (aFrom.X - 1)*iSize,(aFrom.Y - 1)*iSize);
  FTarget.Init( (aTo.X   - 1)*iSize,(aTo.Y   - 1)*iSize);
  if aPartial > 0.0 then
    FTarget := Lerp( FSource, FTarget, aPartial );
  if aPartial < 0.0 then
    FSource := Lerp( FSource, FTarget, 1.0+aPartial );
  FPosition := FSource;
end;

procedure TDoomMove.OnStart;
var iBeing : TBeing;
begin
  iBeing := UIDs.Get( FUID ) as TBeing;
  if iBeing <> nil then iBeing.AnimCount := iBeing.AnimCount + 1;
end;

procedure TDoomMove.OnDraw;
var iValue    : Single;
    iLight    : Byte;
begin
  iValue    := Clampf( FTime / FDuration, 0, 1 );
  iLight    := Lerp( FLightStart, FLightEnd, iValue );
  FPosition := Lerp( FSource, FTarget, iValue );
  SpriteMap.PushSpriteBeing( FPosition, FSprite, iLight );
end;

destructor TDoomMove.Destroy;
var iBeing : TBeing;
begin
  iBeing := UIDs.Get( FUID ) as TBeing;
  if iBeing <> nil then iBeing.AnimCount := Max( 0, iBeing.AnimCount - 1 );
  inherited Destroy;
end;

{ TDoomScreenMove }

constructor TDoomScreenMove.Create( aDuration : DWord; aTo: TCoord2D );
begin
  inherited Create( aDuration, 0, 0 );
  FSource   := SpriteMap.Shift;
  FDest     := SpriteMap.ShiftValue(aTo);
  FDuration := Max( FDuration, Round( Sqrt( FSource.Distance( FDest ) ) ) );
  CCurrent  := Self;
end;

class function TDoomScreenMove.Update( aDuration : DWord; aTo : TCoord2D ) : Boolean;
begin
  if CCurrent = nil then Exit( False );
  CCurrent.OnUpdate( 0 );
  CCurrent.FSource   := SpriteMap.NewShift;
  CCurrent.FDest     := SpriteMap.ShiftValue( aTo );
  CCurrent.FTime     := 0;
  CCurrent.FDuration := Max( aDuration, Round( Sqrt( CCurrent.FSource.Distance( CCurrent.FDest ) ) ) );;
  Exit( True );
end;

procedure TDoomScreenMove.OnUpdate( aTime : DWord );
begin
  inherited OnUpdate( aTime );
  SpriteMap.NewShift := Lerp( FSource, FDest, Minf(FTime/FDuration,1.0) );
end;

procedure TDoomScreenMove.OnDraw;
begin
end;

destructor TDoomScreenMove.Destroy;
begin
  SpriteMap.NewShift := FDest;
  CCurrent := nil;
  inherited Destroy;
end;

constructor TDoomAnimateCell.Create( aDuration : DWord; aDelay : DWord; aCoord : TCoord2D; aSprite : TSprite; aValue : Integer );
begin
  inherited Create( aDuration, aDelay, 0 );
  FCoord := aCoord;
  FSprite := aSprite;
  FValue  := aValue;
end;

procedure TDoomAnimateCell.OnStart;
begin
  Doom.Level.LightFlag[ FCoord, LFANIMATING ] := True;
end;

procedure TDoomAnimateCell.OnDraw;
var iSprite  : TSprite;
    iSegment : Integer;
begin
  iSprite := FSprite;
  iSegment := ( FTime * FValue ) div FDuration;
  if ( iSegment <> FValue ) then
    iSegment += Sgn( FValue );
  if iSprite.SCount > 1 then
  begin
    iSegment := Abs( iSegment );
    iSprite.SpriteID[0] := iSprite.SpriteID[ iSegment ];
  end
  else
    iSprite.SpriteID[0] += ( FValue - iSegment ) * DRL_COLS;
  SpriteMap.PushSpriteDoodad( FCoord, iSprite );
end;

destructor TDoomAnimateCell.Destroy;
begin
  Doom.Level.LightFlag[ FCoord, LFANIMATING ] := False;
  inherited Destroy;
end;

constructor TDoomScreenShake.Create( aDuration : DWord; aDelay : DWord; aStrength : Single );
begin
  inherited Create( aDuration, aDelay, 0 );
  FStrength   := aStrength;
  FFrequencyX := 0.05 + Random;
  FFrequencyY := 0.05 + Random;
end;

class function TDoomScreenShake.Update( aDuration : DWord; aDelay : DWord; aStrength : Single ) : Boolean;
begin
  if CCurrent = nil then Exit( False );
  CCurrent.FStrength := Maxf( CCurrent.FStrength, aStrength );
  CCurrent.FDelay    := Min( CCurrent.FDelay, aDelay );
  CCurrent.FDuration := Max( CCurrent.FDuration, aDuration );
  Exit( True );
end;

procedure TDoomScreenShake.OnUpdate( aTime : DWord );
var iFactor : Single;
    iFade   : Single;
    iOffset : TVec2i;
    iMaxX   : Single;
    iMaxY   : Single;
begin
  inherited OnUpdate( aTime );
  iOffset := Vec2i(0,0);
  if FTime < FDuration then
  begin
    iFactor := Minf( FTime / FDuration, 1.0 );
    iFade   := 1.0 - iFactor * iFactor;
    iMaxX   := FStrength * iFade * 2.0; // X-bias
    iMaxY   := FStrength * iFade;

    iOffset.X := Round(iMaxX * Sin( FTime * FFrequencyX * 2 * Pi ) );
    iOffset.Y := Round(iMaxY * Cos( FTime * FFrequencyY * 1 * Pi ) );
  end;
  if Assigned( SpriteMap ) then SpriteMap.Offset := iOffset;
end;

procedure TDoomScreenShake.OnDraw;
begin
end;

destructor TDoomScreenShake.Destroy;
begin
  if Assigned( SpriteMap ) then SpriteMap.Offset := Vec2i(0,0);
  inherited Destroy;
end;


end.


unit fu_starprofile;

{$mode objfpc}{$H+}

{
Copyright (C) 2015 Patrick Chevalley

http://www.ap-i.net
pch@ap-i.net

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>. 

}

interface

uses  u_modelisation, u_global, u_utils, math, UScaleDPI, fu_preview,
  fu_focuser, Graphics, Classes, SysUtils, FPImage, cu_fits, FileUtil, TAGraph,
  TAFuncSeries, TASeries, TASources, Forms, Controls, StdCtrls, ExtCtrls;

const maxhist=50;

type

  { Tf_starprofile }

  Tf_starprofile = class(TFrame)
    ChkAutofocus: TCheckBox;
    ChkFocus: TCheckBox;
    FitSourceL: TListChartSource;
    FitSourceR: TListChartSource;
    graph: TImage;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    LabelFWHM: TLabel;
    Panel3: TPanel;
    Panel4: TPanel;
    Panel5: TPanel;
    Panel6: TPanel;
    Panel7: TPanel;
    profile: TImage;
    LabelHFD: TLabel;
    LabelImax: TLabel;
    Panel1: TPanel;
    Panel2: TPanel;
    StaticText1: TStaticText;
    VcChart: TChart;
    VcChartL: TFitSeries;
    VcChartR: TFitSeries;
    procedure ChkAutofocusChange(Sender: TObject);
    procedure ChkFocusChange(Sender: TObject);
    procedure FrameEndDrag(Sender, Target: TObject; X, Y: Integer);
    procedure FrameResize(Sender: TObject);
    procedure graphDblClick(Sender: TObject);
  private
    { private declarations }
    FFindStar: boolean;
    FStarX,FStarY,FValMax: double;
    FFocusStart,FFocusStop: TNotifyEvent;
    FAutoFocusStop,FAutoFocusStart: TNotifyEvent;
    FonFocusIN, FonFocusOUT, FonAbsolutePosition: TNotifyEvent;
    FonMsg: TNotifyMsg;
    Fpreview:Tf_preview;
    Ffocuser:Tf_focuser;
    emptybmp:Tbitmap;
    histfwhm, histimax: array[0..maxhist] of double;
    maxfwhm,maximax: double;
    Fhfd,Ffwhm,Ffwhmarcsec,FLastHfd,FSumHfd:double;
    curhist,FfocuserSpeed,FnumHfd: integer;
    focuserdirection,terminated: boolean;
    ahfd: array of double;
    aminhfd,amaxhfd:double;
    afmpos,aminpos:integer;
    procedure msg(txt:string);
    function  getRunning:boolean;
    procedure FindStarPos(img:Timaw16; c,vmin: double; x,y,s,xmax,ymax: integer; out xc,yc:integer; out vmax,bg: double);
    procedure GetPSF(img:Timaw16; c,vmin: double; x,y,s,xmax,ymax: integer; out fwhm: double);
    procedure GetHFD(img:Timaw16; c,vmin: double; x,y,s: integer; var bg: double; out xc,yc,hfd,valmax: double);
    procedure PlotProfile(img:Timaw16; c,vmin,bg: double; s:integer);
    procedure PlotHistory;
    procedure ClearGraph;
    procedure doAutofocusVcurve;
    procedure doAutofocusMean;
    procedure doAutofocusIterative;
  public
    { public declarations }
    constructor Create(aOwner: TComponent); override;
    destructor  Destroy; override;
    procedure FindBrightestPixel(img:Timaw16; c,vmin: double; x,y,s,xmax,ymax: integer; out xc,yc:integer; out vmax: double);
    procedure ShowProfile(img:Timaw16; c,vmin: double; x,y,s,xmax,ymax: integer; focal:double=-1; pxsize:double=-1);
    procedure Autofocus(img:Timaw16; c,vmin: double; x,y,s,xmax,ymax: integer);
    procedure InitAutofocus;
    property AutofocusRunning: boolean read getRunning;
    property FindStar : boolean read FFindStar write FFindStar;
    property HFD:double read Fhfd;
    property ValMax: double read FValMax;
    property StarX: double read FStarX write FStarX;
    property StarY: double read FStarY write FStarY;
    property preview:Tf_preview read Fpreview write Fpreview;
    property focuser:Tf_focuser read Ffocuser write Ffocuser;
    property onMsg: TNotifyMsg read FonMsg write FonMsg;
    property onFocusStart: TNotifyEvent read FFocusStart write FFocusStart;
    property onFocusStop: TNotifyEvent read FFocusStop write FFocusStop;
    property onAutoFocusStart: TNotifyEvent read FAutoFocusStart write FAutoFocusStart;
    property onAutoFocusStop: TNotifyEvent read FAutoFocusStop write FAutoFocusStop;
    property onFocusIN: TNotifyEvent read FonFocusIN write FonFocusIN;
    property onFocusOUT: TNotifyEvent read FonFocusOUT write FonFocusOUT;
    property onAbsolutePosition: TNotifyEvent read FonAbsolutePosition write FonAbsolutePosition;
  end;

implementation

{$R *.lfm}

{ Tf_starprofile }

procedure Tf_starprofile.FrameEndDrag(Sender, Target: TObject; X, Y: Integer);
begin
 if Target is TPanel then begin
    if TPanel(Target).Width>TPanel(Target).Height then begin
       Panel1.ChildSizing.ControlsPerLine:=2;
       Panel1.ChildSizing.Layout:=cclLeftToRightThenTopToBottom;
    end else begin
        Panel1.ChildSizing.ControlsPerLine:=99;
        Panel1.ChildSizing.Layout:=cclTopToBottomThenLeftToRight;
    end;
 end;
end;

procedure Tf_starprofile.ChkFocusChange(Sender: TObject);
begin
 if ChkAutofocus.Checked then begin
   ChkFocus.Checked:=false;
   exit;
 end;
 if ChkFocus.Checked then begin
    if Assigned(FFocusStart) then FFocusStart(self);
 end else begin
   if Assigned(FFocusStop) then FFocusStop(self);
 end;
end;

procedure Tf_starprofile.ChkAutofocusChange(Sender: TObject);
begin
 if ChkFocus.Checked then begin
    ChkAutofocus.Checked:=false;
    exit;
 end;
 if ChkAutofocus.Checked then begin
    if Assigned(FAutoFocusStart) then FAutoFocusStart(self);
 end else begin
   if Assigned(FAutoFocusStop) then FAutoFocusStop(self);
 end;
end;

function  Tf_starprofile.getRunning:boolean;
begin
 result:=ChkAutofocus.Checked;
end;

procedure Tf_starprofile.InitAutofocus;
begin
 FnumHfd:=0;
 FSumHfd:=0;
 terminated:=false;
 FfocuserSpeed:=AutofocusMaxSpeed;
 focuser.FocusSpeed:=FfocuserSpeed;
 focuserdirection:=AutofocusMoveDir;
 AutofocusMeanStep:=afmStart;
 if focuserdirection=FocusDirOut then
    AutofocusVcStep:=vcsNearL
  else
    AutofocusVcStep:=vcsNearR;
 case AutofocusMode of
   afVcurve   : msg('Autofocus start Vcurve');
   afMean     : msg('Autofocus start Mean position');
   afIterative: msg('Autofocus start Iterative focus');
 end;
end;

procedure Tf_starprofile.FrameResize(Sender: TObject);
begin
 if Parent is TPanel then begin
    if TPanel(Parent).Width>TPanel(Parent).Height then begin
       Panel1.ChildSizing.ControlsPerLine:=2;
       Panel1.ChildSizing.Layout:=cclLeftToRightThenTopToBottom;
    end else begin
        Panel1.ChildSizing.ControlsPerLine:=99;
        Panel1.ChildSizing.Layout:=cclTopToBottomThenLeftToRight;
    end;
 end;
end;

procedure Tf_starprofile.graphDblClick(Sender: TObject);
begin
 curhist:=0;
 maxfwhm:=0;
 maximax:=0;
end;

procedure Tf_starprofile.msg(txt:string);
begin
 if assigned(FonMsg) then FonMsg(txt);
end;

procedure Tf_starprofile.ClearGraph;
begin
 profile.Picture.Bitmap.Width:=profile.Width;
 profile.Picture.Bitmap.Height:=profile.Height;
 with profile.Picture.Bitmap do begin
   Canvas.Brush.Color:=clBlack;
   Canvas.Pen.Color:=clBlack;
   Canvas.Pen.Mode:=pmCopy;
   Canvas.FillRect(0,0,Width,Height);
 end;
 graph.Picture.Bitmap.Width:=graph.Width;
 graph.Picture.Bitmap.Height:=graph.Height;
 with graph.Picture.Bitmap do begin
   Canvas.Brush.Color:=clBlack;
   Canvas.Pen.Color:=clBlack;
   Canvas.Pen.Mode:=pmCopy;
   Canvas.FillRect(0,0,Width,Height);
 end;
end;

constructor Tf_starprofile.Create(aOwner: TComponent);
begin
 inherited Create(aOwner);
 ScaleDPI(Self);
 emptybmp:=Tbitmap.Create;
 emptybmp.SetSize(1,1);
 FFindStar:=false;
 curhist:=0;
 maxfwhm:=0;
 maximax:=0;
 focuserdirection:=FocusDirIn;
 FLastHfd:=MaxInt;
 LabelHFD.Caption:='-';
 LabelFWHM.Caption:='-';
 LabelImax.Caption:='-';
 ClearGraph;
end;

destructor  Tf_starprofile.Destroy;
begin
 emptybmp.Free;
 inherited Destroy;
end;

procedure Tf_starprofile.FindBrightestPixel(img:Timaw16; c,vmin: double; x,y,s,xmax,ymax: integer; out xc,yc:integer; out vmax: double);
// brightest pixel in area s*s centered on x,y of image Img of size xmax,ymax
var i,j,rs,xm,ym: integer;
    val:double;
begin
 rs:= s div 2;
 if (x-s)<1 then x:=s+1;
 if (x+s)>(xmax-1) then x:=xmax-s-1;
 if (y-s)<1 then y:=s+1;
 if (y+s)>(ymax-1) then y:=ymax-s-1;
 vmax:=0;
 for i:=-rs to rs do
   for j:=-rs to rs do begin
     Val:=vmin+Img[0,y+j,x+i]/c;
     if Val>vmax then begin
          vmax:=Val;
          xm:=i;
          ym:=j;
     end;
   end;
 xc:=x+xm;
 yc:=y+ym;
end;

procedure Tf_starprofile.FindStarPos(img:Timaw16; c,vmin: double; x,y,s,xmax,ymax: integer; out xc,yc:integer; out vmax,bg: double);
// center of gravity in area s*s centered on x,y of image Img of size xmax,ymax
var i,j,rs: integer;
    SumVal,SumValX,SumValY: double;
    val,xg,yg:double;
begin
  rs:=s div 2;
  if (x-s)<1 then x:=s+1;
  if (x+s)>(xmax-1) then x:=xmax-s-1;
  if (y-s)<1 then y:=s+1;
  if (y+s)>(ymax-1) then y:=ymax-s-1;
  // Compute mean value of the image area
  SumVal:=0;
  for i:=-rs to rs do
   for j:=-rs to rs do begin
     val:=vmin+Img[0,y+j,x+i]/c;
     SumVal:=SumVal+val;
   end;
  bg:=sumval/(4*rs*rs);
  // Get center of gravity of binarized image above mean value
  SumVal:=0;
  SumValX:=0;
  SumValY:=0;
  vmax:=0;
  for i:=-rs to rs do
   for j:=-rs to rs do begin
     val:=vmin+Img[0,y+j,x+i]/c-bg;
     if val>0 then begin
       if val>vmax then vmax:=val;
       SumVal:=SumVal+1;
       SumValX:=SumValX+(i);
       SumValY:=SumValY+(j);
     end;
   end;
  if SumVal>0 then begin
    Xg:=SumValX/SumVal;
    Yg:=SumValY/SumVal;
  end
  else begin
    xg:=0; yg:=0;
  end;
  xc:=round(x+Xg);
  yc:=round(y+Yg);
end;

procedure Tf_starprofile.GetPSF(img:Timaw16; c,vmin: double; x,y,s,xmax,ymax: integer; out fwhm: double);
var simg:TPiw16;
    imgdata: Tiw16;
    PSF:TPSF;
    i,j,rs,x1,y1: integer;
begin
 rs:=s div 2;
 fwhm:=-1;
 setlength(imgdata,s,s);
 simg:=addr(imgdata);
 for i:=0 to s-1 do
   for j:=0 to s-1 do begin
     x1:=x+i-rs;
     y1:=y+j-rs;
     if (x1>0)and(x1<xmax)and(y1>0)and(y1<ymax) then
        imgdata[i,j]:=trunc(vmin+img[0,y1,x1]/c)
     else imgdata[i,j]:=trunc(vmin);
   end;
 PSF.Flux:=0;
 // Get gaussian psf
 ModeliseEtoile(simg,s,TGauss,lowPrecision,LowSelect,0,PSF);
 if PSF.Flux>0 then begin
   fwhm:=PSF.Sigma;
 end;
end;

procedure Tf_starprofile.GetHFD(img:Timaw16; c,vmin: double; x,y,s: integer; var bg: double; out xc,yc,hfd,valmax: double);
var i,j,rs,ri: integer;
    SumVal,SumValX,SumValY,SumValR: double;
    Xg,Yg,fxg,fyg: double;
    r,xs,ys:double;
    noise,snr,val: double;
begin
// x,y must be the star center, bg the mean image value computed by FindStarPos
hfd:=-1;
rs:=s div 2;
// Get radius of interest (x,y must be the star center)
for i:=0 to rs do begin
 for j:=0 to rs do begin
   val:=vmin+Img[0,y+j,x+i]/c;
   if val<=bg then begin
     ri:=ceil(sqrt(i*i+j*j));
     break;
   end;
 end;
 if ri<>rs then break;
end;
if ri<2 then ri:=rs; // Probable central obstruction, use full width instead

// New background from corner values
bg:=vmin+((Img[0,y-ri,x-ri]+Img[0,y-ri,x+ri]+Img[0,y+ri,x-ri]+Img[0,y+ri,x+ri]) / 4)/c;
// Get center of gravity whithin radius of interest
SumVal:=0;
SumValX:=0;
SumValY:=0;
valmax:=0;
for i:=-ri to ri do
 for j:=-ri to ri do begin
   val:=vmin+Img[0,y+j,x+i]/c-bg;
   if val<0 then val:=0;
   if val>valmax then valmax:=val;
   SumVal:=SumVal+val;
   SumValX:=SumValX+val*(i);
   SumValY:=SumValY+val*(j);
 end;
Xg:=SumValX/SumVal;
Yg:=SumValY/SumVal;
xc:=x+Xg;
yc:=y+Yg;
x:=trunc(xc);
y:=trunc(yc);

// Get HFD
fxg:=frac(xc);
fyg:=frac(yc);
SumVal:=0;
SumValR:=0;
noise:=sqrt(bg);
snr:=valmax/noise;
if snr>3 then begin
 for i:=-ri to ri do
   for j:=-ri to ri do begin
     Val:=vmin+Img[0,y+j,x+i]/c-bg;
     if val<0 then val:=0;
     xs:=i+0.5-fxg;
     ys:=j+0.5-fyg;
     r:=sqrt(xs*xs+ys*ys);
     if val>(2*noise) then begin
       SumVal:=SumVal+Val;
       SumValR:=SumValR+Val*r;
     end;
   end;
 hfd:=2*SumValR/SumVal;
end;
end;

procedure Tf_starprofile.PlotProfile(img:Timaw16; c,vmin,bg: double; s:integer);
var i,j,i0,x1,x2,y1,y2:integer;
    xs,ys: double;
    txt:string;
begin
if (StarX<0)or(StarY<0)or(s<0) then exit;
// labels
LabelHFD.Caption:=FormatFloat(f1,Fhfd);
LabelImax.Caption:=FormatFloat(f0,FValMax);
if Ffwhm>0 then begin
  txt:=FormatFloat(f1,Ffwhm);
  if Ffwhmarcsec>0 then txt:=txt+'/'+FormatFloat(f1,Ffwhmarcsec)+'"';
  LabelFWHM.Caption:=txt;
end
else
  LabelFWHM.Caption:='-';
if curhist>maxhist then
  for i:=0 to maxhist-1 do begin
    histfwhm[i]:=histfwhm[i+1];
    histimax[i]:=histimax[i+1];
    curhist:=maxhist;
  end;
histfwhm[curhist]:=Fhfd;
histimax[curhist]:=FValMax;
if histfwhm[curhist] > maxfwhm then maxfwhm:=histfwhm[curhist];
if histimax[curhist] > maximax then maximax:=histimax[curhist];
// Star profile
profile.Picture.Bitmap.Width:=profile.Width;
profile.Picture.Bitmap.Height:=profile.Height;
with profile.Picture.Bitmap do begin
  Canvas.Brush.Color:=clBlack;
  Canvas.Pen.Color:=clBlack;
  Canvas.Pen.Mode:=pmCopy;
  Canvas.FillRect(0,0,Width,Height);
  if FValMax>0 then begin
    Canvas.Pen.Color:=clRed;
    xs:=Width/s;
    ys:=Height/(1.05*FValMax);
    j:=trunc(FStarY);
    i0:=trunc(FStarX)-(s div 2);
    x1:=0;
    y1:=Height-trunc((vmin+(img[0,j,i0]/c)-bg)*ys);
    for i:=0 to s-1 do begin
      x2:=trunc(i*xs);
      y2:=trunc((vmin+(img[0,j,i0+i]/c)-bg)*ys);
      y2:=Height-y2;
      Canvas.Line(x1,y1,x2,y2);
      x1:=x2;
      y1:=y2;
    end;
  end;
end;
// History graph
graph.Picture.Bitmap.Width:=graph.Width;
graph.Picture.Bitmap.Height:=graph.Height;
if FValMax>0 then with graph.Picture.Bitmap do begin
  Canvas.Brush.Color:=clBlack;
  Canvas.Pen.Color:=clBlack;
  Canvas.Pen.Mode:=pmCopy;
  Canvas.FillRect(0,0,Width,Height);
  xs:=Width/maxhist;
  ys:=Height/maxfwhm;
  Canvas.Pen.Color:=clRed;
  for i:=0 to curhist-1 do begin
    Canvas.Line( trunc(i*xs),
                 Height-trunc(histfwhm[i]*ys),
                 trunc((i+1)*xs),
                 Height-trunc(histfwhm[i+1]*ys));
  end;
  ys:=Height/maximax;
  Canvas.Pen.Color:=clLime;
  for i:=0 to curhist-1 do begin
    Canvas.Line( trunc(i*xs),
                 Height-trunc(histimax[i]*ys),
                 trunc((i+1)*xs),
                 Height-trunc(histimax[i+1]*ys));
  end;
end;
inc(curhist);
end;

procedure Tf_starprofile.PlotHistory;
var i:integer;
    xs,ys: double;
begin
if curhist>maxhist then
  for i:=0 to maxhist-1 do begin
    histfwhm[i]:=histfwhm[i+1];
    histimax[i]:=histimax[i+1];
    curhist:=maxhist;
  end;
histfwhm[curhist]:=Fhfd;
histimax[curhist]:=FValMax;
if histfwhm[curhist] > maxfwhm then maxfwhm:=histfwhm[curhist];
if histimax[curhist] > maximax then maximax:=histimax[curhist];
// History graph
graph.Picture.Bitmap.Width:=graph.Width;
graph.Picture.Bitmap.Height:=graph.Height;
if FValMax>0 then with graph.Picture.Bitmap do begin
  Canvas.Brush.Color:=clBlack;
  Canvas.Pen.Color:=clBlack;
  Canvas.Pen.Mode:=pmCopy;
  Canvas.FillRect(0,0,Width,Height);
  xs:=Width/maxhist;
  ys:=Height/maxfwhm;
  Canvas.Pen.Color:=clRed;
  for i:=0 to curhist-1 do begin
    Canvas.Line( trunc(i*xs),
                 Height-trunc(histfwhm[i]*ys),
                 trunc((i+1)*xs),
                 Height-trunc(histfwhm[i+1]*ys));
  end;
  ys:=Height/maximax;
  Canvas.Pen.Color:=clLime;
  for i:=0 to curhist-1 do begin
    Canvas.Line( trunc(i*xs),
                 Height-trunc(histimax[i]*ys),
                 trunc((i+1)*xs),
                 Height-trunc(histimax[i+1]*ys));
  end;
end;
inc(curhist);
end;

procedure Tf_starprofile.ShowProfile(img:Timaw16; c,vmin: double; x,y,s,xmax,ymax: integer; focal:double=-1; pxsize:double=-1);
var bg: double;
  xg,yg: double;
  xm,ym: integer;
begin
 if (x<0)or(y<0)or(s<0) then exit;

 FindStarPos(img,c,vmin,x,y,s,xmax,ymax,xm,ym,FValMax,bg);
 if FValMax=0 then exit;

 GetPSF(img,c,vmin,xm,ym,s,xmax,ymax,Ffwhm);
 if (Ffwhm>0)and(focal>0)and(pxsize>0) then begin
   Ffwhmarcsec:=Ffwhm*3600*rad2deg*arctan(pxsize/1000/focal);
 end
 else Ffwhmarcsec:=-1;

 GetHFD(img,c,vmin,xm,ym,s,bg,xg,yg,Fhfd,FValMax);

 // Plot result
 if (Fhfd>0) then begin
   FFindStar:=true;
   FStarX:=round(xg);
   FStarY:=round(yg);
   PlotProfile(img,c,vmin,bg,s);
   PlotHistory;
 end else begin
   FFindStar:=false;
   LabelHFD.Caption:='-';
   LabelFWHM.Caption:='-';
   LabelImax.Caption:='-';
   ClearGraph;
 end;
end;

procedure Tf_starprofile.Autofocus(img:Timaw16; c,vmin: double; x,y,s,xmax,ymax: integer);
var bg: double;
  xg,yg: double;
  xm,ym: integer;
begin
 if (x<0)or(y<0)or(s<0) then exit;
  FindStarPos(img,c,vmin,x,y,s,xmax,ymax,xm,ym,FValMax,bg);
  if FValMax=0 then begin
    if Fpreview.Exposure=AutofocusExposure
       then begin
         ChkAutofocus.Checked:=false;
         exit;
       end
       else begin
          Fpreview.Exposure:=AutofocusExposure;
          exit;
       end;
  end;
  GetHFD(img,c,vmin,xm,ym,s,bg,xg,yg,Fhfd,FValMax);
  // process this measurement
  if (Fhfd>0) then begin
    if (Fhfd<(AutofocusNearHFD+1))and(not terminated) then begin
      FSumHfd:=FSumHfd+Fhfd;
      inc(FnumHfd);
      msg('Autofocus mean frame '+inttostr(FnumHfd)+'/'+inttostr(AutofocusNearNum));
      if FnumHfd>=AutofocusNearNum then begin  // mean of measurement
        Fhfd:=FSumHfd/FnumHfd;
        FnumHfd:=0;
        FSumHfd:=0;
      end
      else begin
        exit;
      end;
    end;
    // plot progress
    FFindStar:=true;
    FStarX:=round(xg);
    FStarY:=round(yg);
    Ffwhm:=-1;
    PlotProfile(img,c,vmin,bg,s);
    if terminated then begin
      ChkAutofocus.Checked:=false; // focus reached
      msg('Autofocus terminated, HFD='+FormatFloat(f1,Fhfd));
      exit;
    end;
    msg('Autofocus running, HFD='+FormatFloat(f1,Fhfd));
    // do focus
    case AutofocusMode of
      afVcurve   : doAutofocusVcurve;
      afMean     : doAutofocusMean;
      afIterative: doAutofocusIterative;
    end;
  end;
end;

procedure Tf_starprofile.doAutofocusVcurve;
var newpos:double;
begin
 case AutofocusVcStep of
   vcsNearL: begin
              focuser.FocusPosition:=round(AutofocusVc[0,1]);
              wait(1);
              focuser.FocusPosition:=round(AutofocusVc[PosNearL,1]);
              msg('Autofocus move to '+focuser.Position.Text);
              FonAbsolutePosition(self);
              AutofocusVcStep:=vcsFocusL;
              wait(1);
             end;
   vcsNearR: begin
              focuser.FocusPosition:=round(AutofocusVc[AutofocusVcNum,1]);
              wait(1);
              focuser.FocusPosition:=round(AutofocusVc[PosNearR,1]);
              msg('Autofocus move to '+focuser.Position.Text);
              FonAbsolutePosition(self);
              AutofocusVcStep:=vcsFocusR;
              wait(1);
             end;
   vcsFocusL:begin
              newpos:=focuser.FocusPosition-(Fhfd/AutofocusVcSlopeL)+AutofocusVcPID/2;
              focuser.FocusPosition:=round(newpos);
              msg('Autofocus move to '+focuser.Position.Text);
              FonAbsolutePosition(self);
              terminated:=true;
              wait(1);
             end;
   vcsFocusR:begin
              newpos:=focuser.FocusPosition-Fhfd/AutofocusVcSlopeR-AutofocusVcPID/2;
              focuser.FocusPosition:=round(newpos);
              msg('Autofocus move to '+focuser.Position.Text);
              FonAbsolutePosition(self);
              terminated:=true;
              wait(1);
             end;
 end;
end;

procedure Tf_starprofile.doAutofocusMean;
var i,k,step: integer;
    VcpiL,VcpiR,al,bl,rl,ar,br,rr: double;
    p:array of TDouble2;
  procedure ResetPos;
  begin
    k:=AutofocusMeanNumPoint div 2;
    focuser.FocusSpeed:=AutofocusMeanMovement*(k+1);
    if AutofocusMoveDir=FocusDirIn then begin
      onFocusOUT(self);
      Wait(1);
      focuser.FocusSpeed:=AutofocusMeanMovement;
      onFocusIN(self)
    end
    else begin
      onFocusIN(self);
      Wait(1);
      focuser.FocusSpeed:=AutofocusMeanMovement;
      onFocusOUT(self);
    end;
    Wait(1);
  end;
begin
  case AutofocusMeanStep of
    afmStart: begin
              if not odd(AutofocusMeanNumPoint) then
                inc(AutofocusMeanNumPoint);
              if AutofocusMeanNumPoint<5 then AutofocusMeanNumPoint:=5;
              SetLength(ahfd,AutofocusMeanNumPoint);
              // set initial position
              k:=AutofocusMeanNumPoint div 2;
              focuser.FocusSpeed:=AutofocusMeanMovement*(k+1);
              if AutofocusMoveDir=FocusDirIn then begin
                onFocusOUT(self);
                Wait(1);
                focuser.FocusSpeed:=AutofocusMeanMovement;
                onFocusIN(self)
              end
              else begin
                onFocusIN(self);
                Wait(1);
                focuser.FocusSpeed:=AutofocusMeanMovement;
                onFocusOUT(self);
              end;
              Wait(1);
              afmpos:=-1;
              aminhfd:=9999;
              amaxhfd:=-1;
              AutofocusMeanStep:=afmMeasure;
              end;
    afmMeasure: begin
              // store hfd
              inc(afmpos);
              ahfd[afmpos]:=Fhfd;
              if Fhfd<aminhfd then begin
                aminhfd:=Fhfd;
                aminpos:=afmpos;
              end;
              if Fhfd>amaxhfd then begin
                amaxhfd:=Fhfd;
              end;
              // increment position
              if AutofocusMoveDir=FocusDirIn then
                onFocusIN(self)
              else
                onFocusOUT(self);
              wait(1);
              if afmpos=(AutofocusMeanNumPoint-1) then AutofocusMeanStep:=afmEnd;
              end;
    afmEnd: begin
              // check measure validity
              if (aminpos<2)or((AutofocusMeanNumPoint-aminpos-1)<2) then begin
                 msg('Not enough points on left or right of focus position,');
                 msg('Try to start with a better position or increase the movement.');
                 ResetPos;
                 terminated:=true;
                 exit;
              end;
              if (amaxhfd<(3*aminhfd)) then begin
                 msg('Too small HFD difference,');
                 msg('Try to increase the number of point or the movement.');
                 ResetPos;
                 terminated:=true;
                 exit;
              end;
              // compute focus
              k:=aminpos;
              // left part
              SetLength(p,k);
              for i:=0 to k-1 do begin
                p[i,1]:=i+1;
                p[i,2]:=ahfd[i];
              end;
              LeastSquares(p,al,bl,rl);
              VcpiL:=-bl/al;
              // right part
              k:=AutofocusMeanNumPoint-k-1;
              SetLength(p,k);
              for i:=0 to k-1 do begin
                p[i,1]:=aminpos+2+i;
                p[i,2]:=ahfd[aminpos+1+i];
              end;
              LeastSquares(p,ar,br,rr);
              VcpiR:=-br/ar;
              // focus position
              step:=round(AutofocusMeanMovement*(VcpiL+VcpiR)/2);
              focuser.FocusSpeed:=step+AutofocusMeanMovement;
              if AutofocusMoveDir=FocusDirIn then begin
                onFocusOUT(self);
                wait(1);
                focuser.FocusSpeed:=AutofocusMeanMovement;
                onFocusIN(self);
              end
              else begin
                onFocusIN(self);
                wait(1);
                focuser.FocusSpeed:=AutofocusMeanMovement;
                onFocusOUT(self)
              end;
              wait(1);
              terminated:=true;
              end;
  end;
end;

procedure Tf_starprofile.doAutofocusIterative;
begin
  if Fhfd>FLastHfd then begin  // reverse direction
    if FfocuserSpeed=AutofocusMinSpeed  then begin
      // we reach focus, go back one step and terminate
      focuserdirection:=not focuserdirection;
      terminated:=true;
    end else begin
      if Fhfd<=AutofocusNearHFD then begin
         FfocuserSpeed:=max(FfocuserSpeed div 2,AutofocusMinSpeed);   // divide speed by 2
         focuser.FocusSpeed:=FfocuserSpeed; // set new speed
      end;
      focuserdirection:=not focuserdirection;
    end;
  end;
  if focuserdirection=FocusDirIn
     then begin
        msg('Autofocus focus in by '+inttostr(FfocuserSpeed));
        FonFocusIN(self);
      end
     else begin
       msg('Autofocus focus out by '+inttostr(FfocuserSpeed));
       FonFocusOUT(self);
     end;
  FLastHfd:=Fhfd;
end;

end.


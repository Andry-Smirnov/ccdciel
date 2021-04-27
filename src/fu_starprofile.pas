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

uses BGRABitmap, BGRABitmapTypes, u_global, u_utils, math, UScaleDPI, u_hints, u_translation,
  fu_preview, fu_focuser, Graphics, Classes, SysUtils, FPImage, cu_fits, pu_hyperbola, pu_image_sharpness,
  FileUtil, TAGraph, TAFuncSeries, TASeries, TASources, TAChartUtils, Forms, Controls,
  StdCtrls, ExtCtrls, Buttons, LCLType, ComCtrls;

const maxhist=50;

type

  { Tf_starprofile }

  Tf_starprofile = class(TFrame)
    BtnMeasureImage: TButton;
    BtnPin2D: TSpeedButton;
    BtnPinProfile: TSpeedButton;
    BtnPinTrend: TSpeedButton;
    BtnViewAutofocus: TButton;
    FitSourceMeasure: TListChartSource;
    FitSourceComp: TListChartSource;
    HistoryChartImax: TLineSeries;
    Panel2: TPanel;
    PanelBtnPin2D: TPanel;
    PanelBtnProfile: TPanel;
    PanelBtnTrend: TPanel;
    Star2D: TImage;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    LabelHistHFD: TLabel;
    LabelCoord: TLabel;
    LabelFWHM: TLabel;
    LabelSNR: TLabel;
    HistoryChart: TChart;
    HistoryChartHfd: TLineSeries;
    HistSourceHfd: TListChartSource;
    HistSourceImax: TListChartSource;
    PageControlProfile: TPageControl;
    Panel7: TPanel;
    ProfileSource: TListChartSource;
    Panel4: TPanel;
    Panel5: TPanel;
    PanelGraph: TPanel;
    PanelFWHM: TPanel;
    Panel6: TPanel;
    LabelHFD: TLabel;
    LabelImax: TLabel;
    Panel1: TPanel;
    ChkFocus: TSpeedButton;
    ChkAutofocus: TSpeedButton;
    PtSourceMeasure: TListChartSource;
    PtSourceComp: TListChartSource;
    BtnPinGraph: TSpeedButton;
    TSprofile: TTabSheet;
    TS2d: TTabSheet;
    TStrend: TTabSheet;
    Title: TLabel;
    TimerHideGraph: TTimer;
    VcChart: TChart;
    ProfileChart: TChart;
    VcChartL: TFitSeries;
    VcChartPtMeasure: TLineSeries;
    VcChartPtComp: TLineSeries;
    ProfileChartLine: TLineSeries;
    VcChartR: TFitSeries;
    VcChartRegMeasure: TLineSeries;
    VcChartRegComp: TLineSeries;
    procedure BtnPin2DClick(Sender: TObject);
    procedure BtnPinGraphClick(Sender: TObject);
    procedure BtnPinProfileClick(Sender: TObject);
    procedure BtnPinTrendClick(Sender: TObject);
    procedure BtnViewAutofocusClick(Sender: TObject);
    procedure ChkAutofocusChange(Sender: TObject);
    procedure ChkFocusChange(Sender: TObject);
    procedure BtnMeasureImageClick(Sender: TObject);
    procedure HistoryChartDblClick(Sender: TObject);
    procedure HistoryChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PageControlProfileChange(Sender: TObject);
    procedure PanelGraphDblClick(Sender: TObject);
    procedure TimerHideGraphTimer(Sender: TObject);
    procedure VcChartMouseMove(Sender: TObject; Shift: TShiftState; X,
      Y: Integer);
  private
    { private declarations }
    FFindStar: boolean;
    FStarX,FStarY,FValMax,FValMaxCalibrated: double;
    FFocusStart,FFocusStop: TNotifyEvent;
    FAutoFocusStop,FAutoFocusStart: TNotifyEvent;
    FonFocusIN, FonFocusOUT, FonAbsolutePosition: TNotifyEvent;
    FonMeasureImage: TNotifyBoolConst;
    FonStarSelection: TNotifyEvent;
    FonMsg: TNotifyMsg;
    FonStatus: TNotifyStr;
    Fpreview:Tf_preview;
    Ffocuser:Tf_focuser;
    emptybmp:Tbitmap;
    histfwhm, histimax: array[0..maxhist] of double;
    maxfwhm,maximax: double;
    Fhfd,Ffwhm,Ffwhmarcsec,FLastHfd,Fsnr,FMinSnr,FminPeak:double;
    FhfdList: array of double;
    curhist,FfocuserSpeed,FnumHfd,FPreFocusPos,FnumGraph,FAutofocusRestart: integer;
    focuserdirection,terminated,FirstFrame: boolean;
    FAutofocusResult, FAutofocusDone: boolean;
    dyn_v_curve:array of TDouble2;
    aminhfd,amaxhfd:double;
    afmpos,aminpos,DynAbsStartPos,DynAbsStep:integer;
    ColorImg: TBGRABitmap;
    procedure msg(txt:string; level: integer);
    function  getRunning:boolean;
    procedure PlotProfile(f: TFits; bg: double; s:integer);
    procedure PlotHistory;
    procedure ClearGraph;
    procedure doAutofocusVcurve;
    procedure doAutofocusDynamic;
    procedure doAutofocusIterative;
    procedure doAutofocusPlanet;
    procedure PanelGraphClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure Panel2DClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure PanelProfileClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure PanelTrendClose(Sender: TObject; var CloseAction: TCloseAction);
  public
    { public declarations }
    LastFocusimage: TBGRABitmap;
    LastFocusMsg: string;
    constructor Create(aOwner: TComponent); override;
    destructor  Destroy; override;
    procedure SetLang;
    procedure ShowProfile(f: TFits; x,y,s: integer; focal:double=-1; pxsize:double=-1);
    procedure ShowSharpness(f: TFits);
    procedure Autofocus(f: TFits; x,y,s: integer);
    procedure InitAutofocus(restart: boolean);
    procedure ChkFocusDown(value:boolean);
    procedure ChkAutoFocusDown(value:boolean);
    property AutofocusRunning: boolean read getRunning;
    property FindStar : boolean read FFindStar write FFindStar;
    property HFD:double read Fhfd;
    property SNR:double read Fsnr;
    property ValMax: double read FValMax;
    property ValMaxCalibrated: double read FValMaxCalibrated;
    property PreFocusPos: integer read FPreFocusPos write FPreFocusPos;
    property StarX: double read FStarX write FStarX;
    property StarY: double read FStarY write FStarY;
    property AutofocusResult: boolean read FAutofocusResult write FAutofocusResult;
    property AutofocusDone: boolean read FAutofocusDone;
    property preview:Tf_preview read Fpreview write Fpreview;
    property focuser:Tf_focuser read Ffocuser write Ffocuser;
    property onMsg: TNotifyMsg read FonMsg write FonMsg;
    property onStatus: TNotifyStr read FonStatus write FonStatus;
    property onFocusStart: TNotifyEvent read FFocusStart write FFocusStart;
    property onFocusStop: TNotifyEvent read FFocusStop write FFocusStop;
    property onAutoFocusStart: TNotifyEvent read FAutoFocusStart write FAutoFocusStart;
    property onAutoFocusStop: TNotifyEvent read FAutoFocusStop write FAutoFocusStop;
    property onFocusIN: TNotifyEvent read FonFocusIN write FonFocusIN;
    property onFocusOUT: TNotifyEvent read FonFocusOUT write FonFocusOUT;
    property onAbsolutePosition: TNotifyEvent read FonAbsolutePosition write FonAbsolutePosition;
    property onMeasureImage: TNotifyBoolConst read FonMeasureImage write FonMeasureImage;
    property onStarSelection: TNotifyEvent read FonStarSelection write FonStarSelection;
  end;

implementation

{$R *.lfm}

{ Tf_starprofile }

constructor Tf_starprofile.Create(aOwner: TComponent);
begin
 inherited Create(aOwner);
 {$ifdef lclcocoa}
 Title.Color:=clWindowFrame;
 Panel1.ChildSizing.LeftRightSpacing:=8;
 Panel1.ChildSizing.VerticalSpacing:=4;
 BtnPinGraph.Flat:=true;
 ChkFocus.Flat:=true;
 ChkAutofocus.Flat:=true;
 ChkFocus.Transparent:=false;
 ChkAutofocus.Transparent:=false;
 {$endif}
 ScaleDPI(Self);
 SetLang;
 emptybmp:=Tbitmap.Create;
 emptybmp.SetSize(1,1);
 ColorImg:=TBGRABitmap.Create;
 LastFocusimage:=TBGRABitmap.Create(1,1);
 LastFocusMsg:='Autofocus not run';
 FAutofocusDone:=false;
 FFindStar:=false;
 curhist:=0;
 maxfwhm:=0.0001;
 maximax:=0.0001;
 FPreFocusPos:=-1;
 focuserdirection:=FocusDirIn;
 FLastHfd:=MaxInt;
 LabelHFD.Caption:='-';
 LabelHistHFD.Caption:='';
 LabelFWHM.Caption:='-';
 LabelImax.Caption:='-';
 LabelSNR.Caption:='-';
 ClearGraph;
 BtnViewAutofocus.Enabled:=false;
 PageControlProfile.ActivePageIndex:=0;
end;

destructor  Tf_starprofile.Destroy;
begin
 emptybmp.Free;
 LastFocusimage.Free;
 ColorImg.Free;
 inherited Destroy;
end;

procedure Tf_starprofile.SetLang;
begin
  Title.Caption:=rsFocus;
  TSprofile.Caption:=rsProfile2;
  TS2d.Caption:=rs2D;
  TStrend.Caption:=rsTrend;
  Label1.Caption:=rsHFD+':';
  Label5.Caption:=rsHistory;
  Label2.Caption:=rsIntensity+':';
  Label3.Caption:=rsFWHM+':';
  BtnMeasureImage.Caption:=rsImageInspect;
  ChkFocus.Caption:=rsManualFocusA;
  ChkAutofocus.Caption:=rsAutofocus;
  BtnViewAutofocus.Caption:=rsViewLastAuto;
  ProfileChart.Hint:=rsTheSelectedS;
  HistoryChart.Hint:=rsHistoryOfThe;
  LabelHFD.Hint:=rsTheHalfFluxD;
  LabelImax.Hint:=rsTheMaximumIn;
  LabelSNR.Hint:=rsTheSignalNoi;
  LabelFWHM.Hint:=rsTheFullWidth;
  BtnPinGraph.Hint:=rsKeepTheGraph;
  BtnMeasureImage.Hint:=rsInspectTheRe;
  ChkFocus.Hint:=rsStartImageLo;
  ChkAutofocus.Hint:=rsStartTheAuto;
end;

procedure Tf_starprofile.ChkFocusDown(value:boolean);
begin
  ChkFocus.Down:=value;
  ChkFocusChange(ChkFocus);
end;

procedure Tf_starprofile.ChkAutoFocusDown(value:boolean);
begin
 ChkAutofocus.Down:=value;
 ChkAutofocusChange(ChkAutofocus);
end;

procedure Tf_starprofile.ChkFocusChange(Sender: TObject);
begin
 if ChkAutofocus.Down then begin
   ChkFocus.Down:=false;
   exit;
 end;
 if ChkFocus.Down then begin
    PanelFWHM.Visible:=true;
    PanelGraph.Visible:=false;
    if Assigned(FFocusStart) then FFocusStart(self);
 end else begin
   if Assigned(FFocusStop) then FFocusStop(self);
 end;
end;

procedure Tf_starprofile.ChkAutofocusChange(Sender: TObject);
begin
 if ChkFocus.Down then begin
    ChkAutofocus.Down:=false;
    exit;
 end;
 if ChkAutofocus.Down then begin
    BtnViewAutofocus.Enabled:=false;
    if Assigned(FAutoFocusStart) then FAutoFocusStart(self);
 end else begin
   terminated:=true;
   BtnViewAutofocus.Enabled:=true;
   if Assigned(FAutoFocusStop) then FAutoFocusStop(self);
 end;
end;

function  Tf_starprofile.getRunning:boolean;
begin
 result:=ChkAutofocus.Down;
end;

procedure Tf_starprofile.InitAutofocus(restart: boolean);
var i: integer;
begin
 FnumHfd:=0;
 FnumGraph:=0;
 SetLength(FhfdList,AutofocusNearNum);
 FMinSnr:=99999;
 FminPeak:=9999999;
 terminated:=false;
 FirstFrame:=true;
 FAutofocusResult:=false;
 FPreFocusPos:=focuser.FocusPosition;
 focuserdirection:=AutofocusMoveDir;
 PtSourceMeasure.Clear;
 FitSourceMeasure.Clear;
 PtSourceComp.Clear;
 FitSourceComp.Clear;
 PanelFWHM.Visible:=false;
 PanelGraph.Visible:=true;
 if restart then
    inc(FAutofocusRestart)
 else
    FAutofocusRestart:=0;
 case AutofocusMode of
   afVcurve   : begin
                // plot curve in graph
                if AutofocusMode=afVcurve then begin
                  for i:=0 to AutofocusVcNum do begin
                    FitSourceMeasure.Add(AutofocusVc[i,1],AutofocusVc[i,2]);
                  end;
                end;
                msg(rsAutofocusSta3,2);
                if focuserdirection=FocusDirOut then
                   AutofocusVcStep:=vcsStartL
                 else
                   AutofocusVcStep:=vcsStartR;
                end;
   afDynamic  : begin
                msg(rsAutofocusSta4,2);
                AutofocusDynamicStep:=afdStart;
                end;
   afIterative: begin
                msg(rsAutofocusSta5,2);
                FfocuserSpeed:=AutofocusMaxSpeed;
                focuser.FocusSpeed:=FfocuserSpeed;
                end;
   afPlanet   : begin
                msg(rsAutofocusSta6,2);
                AutofocusPlanetStep:=afpStart;
                end;
 end;
end;

procedure Tf_starprofile.HistoryChartDblClick(Sender: TObject);
begin
 curhist:=0;
 maxfwhm:=0.0001;
 maximax:=0.0001;
 ClearGraph;
end;

procedure Tf_starprofile.HistoryChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var dx,d,vhfd,vimax: Double;
    i: integer;
begin
 d:=99999;
 vhfd:=-1;
 for i:=0 to HistSourceHfd.Count-1 do begin
   dx:=abs(X-HistoryChart.XGraphToImage(HistSourceHfd.Item[i]^.X));
   if dx<d then begin
     d:=dx;
     vhfd:=HistSourceHfd.Item[i]^.Y;
     vimax:=HistSourceImax.Item[i]^.Y*maximax/maxfwhm;
   end;
 end;
 if (vhfd>0) and assigned(FonStatus) then FonStatus(rsHFD+':'+formatfloat(f1,vhfd)+' '+rsIntensity+':'+formatfloat(f0,vimax));
end;

procedure Tf_starprofile.PageControlProfileChange(Sender: TObject);
begin
  case PageControlProfile.ActivePageIndex of
    0: begin PanelBtnProfile.SendToBack; PanelBtnProfile.BringToFront; end;
    1: begin BtnPin2D.SendToBack; BtnPin2D.BringToFront; end;
    2: begin PanelBtnTrend.SendToBack; PanelBtnTrend.BringToFront; end;
  end;
end;

procedure Tf_starprofile.BtnMeasureImageClick(Sender: TObject);
begin
  if assigned(FonMeasureImage) then FonMeasureImage(true);
end;

procedure Tf_starprofile.BtnPin2DClick(Sender: TObject);
var f: TForm;
begin
  if Star2D.Parent=Panel2 then begin
   f:=TForm.Create(self);
   f.FormStyle:=fsStayOnTop;
   f.OnClose:=@Panel2DClose;
   f.Width:=DoScaleX(400);
   f.Height:=DoScaleY(300);
   f.Caption:=rs2D;
   f.Color:=clBlack;
   Star2D.Parent:=f;
   Star2D.Align:=alClient;
   FormPos(f,mouse.CursorPos.x,mouse.CursorPos.y);
   f.Show;
  end
  else if Star2D.Parent is TForm then
   TForm(Star2D.Parent).Close;
end;

procedure Tf_starprofile.Panel2DClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction:=caFree;
  Star2D.Parent:=Panel2;
  PanelBtnPin2D.SendToBack;
  PanelBtnPin2D.BringToFront;
end;

procedure Tf_starprofile.BtnPinProfileClick(Sender: TObject);
var f: TForm;
begin
  if ProfileChart.Parent=TSprofile then begin
   f:=TForm.Create(self);
   f.FormStyle:=fsStayOnTop;
   f.OnClose:=@PanelProfileClose;
   f.Width:=DoScaleX(400);
   f.Height:=DoScaleY(300);
   f.Caption:=rsProfile2;
   ProfileChart.Parent:=f;
   ProfileChart.Align:=alClient;
   FormPos(f,mouse.CursorPos.x,mouse.CursorPos.y);
   f.Show;
  end
  else if ProfileChart.Parent is TForm then
   TForm(ProfileChart.Parent).Close;
end;

procedure Tf_starprofile.PanelProfileClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction:=caFree;
  ProfileChart.Parent:=TSprofile;
  PanelBtnProfile.SendToBack;
  PanelBtnProfile.BringToFront;
end;

procedure Tf_starprofile.BtnPinTrendClick(Sender: TObject);
var f: TForm;
begin
  if HistoryChart.Parent=TStrend then begin
   f:=TForm.Create(self);
   f.FormStyle:=fsStayOnTop;
   f.OnClose:=@PanelTrendClose;
   f.Width:=DoScaleX(400);
   f.Height:=DoScaleY(300);
   f.Caption:=rsTrend;
   HistoryChart.Parent:=f;
   HistoryChart.Align:=alClient;
   FormPos(f,mouse.CursorPos.x,mouse.CursorPos.y);
   f.Show;
  end
  else if HistoryChart.Parent is TForm then
   TForm(HistoryChart.Parent).Close;
end;

procedure Tf_starprofile.PanelTrendClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction:=caFree;
  HistoryChart.Parent:=TStrend;
  PanelBtnTrend.SendToBack;
  PanelBtnTrend.BringToFront;
end;

procedure Tf_starprofile.BtnPinGraphClick(Sender: TObject);
begin
  if BtnPinGraph.Down then PanelGraphDblClick(Sender);
end;

procedure Tf_starprofile.BtnViewAutofocusClick(Sender: TObject);
begin
 PanelGraph.Visible:=not PanelGraph.Visible;
 PanelFWHM.Visible:=not PanelGraph.Visible;
end;

procedure Tf_starprofile.PanelGraphDblClick(Sender: TObject);
var f: TForm;
begin
 if PanelGraph.Parent=Panel6 then begin
  f:=TForm.Create(self);
  f.FormStyle:=fsStayOnTop;
  f.OnClose:=@PanelGraphClose;
  f.Width:=DoScaleX(400);
  f.Height:=DoScaleY(300);
  f.Caption:=rsAutofocusGra;
  PanelGraph.Parent:=f;
  PanelGraph.Align:=alClient;
  BtnPinGraph.Down:=true;
  VcChart.AxisList.Axes[0].Marks.LabelFont.Height:=0;
  VcChart.AxisList.Axes[1].Marks.LabelFont.Height:=0;
  FormPos(f,mouse.CursorPos.x,mouse.CursorPos.y);
  f.Show;
 end;
end;

procedure Tf_starprofile.PanelGraphClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction:=caFree;
  PanelGraph.Align:=alNone;
  PanelGraph.Parent:=Panel6;
  VcChart.AxisList.Axes[0].Marks.LabelFont.Height:=8;
  VcChart.AxisList.Axes[1].Marks.LabelFont.Height:=8;
end;

procedure Tf_starprofile.TimerHideGraphTimer(Sender: TObject);
begin
 if BtnPinGraph.Down then begin
   TimerHideGraph.Interval:=1000;
 end
 else begin
   TimerHideGraph.Enabled:=false;
   if (PanelGraph.Parent<>Panel6)and(PanelGraph.Parent is TForm) then begin
     TForm(PanelGraph.Parent).close;
   end;
   PanelFWHM.Visible:=true;
   PanelGraph.Visible:=false;
 end;
end;


procedure Tf_starprofile.VcChartMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var pointi: TPoint;
    pointg: TDoublePoint;
    i: integer;
    d,dx,dy,r,newx,newy:double;
begin
  if (x>5)and(x<(VcChart.Width-5))and(y>5)and(y<(VcChart.Height-5)) then begin
  try
  // mouse position
  pointi.x:=X;
  pointi.y:=Y;
  pointg:=VcChart.ImageToGraph(pointi);
  // maximum search radius 5 pixel
  r:=5;
  newx:=-1;
  newy:=-1;
  // search computed focus point
  if PtSourceComp.Count>0 then begin
    dx:=X-VcChart.XGraphToImage(PtSourceComp.Item[0]^.X);
    dy:=Y-VcChart.YGraphToImage(PtSourceComp.Item[0]^.Y);
    d:=sqrt(dx*dx+dy*dy);
    if d<r then begin
      newx:=PtSourceComp.Item[0]^.X;
      newy:=PtSourceComp.Item[0]^.Y;
      r:=d;
    end;
  end;
  // search measured point
  for i:=0 to PtSourceMeasure.Count-1 do begin
    dx:=X-VcChart.XGraphToImage(PtSourceMeasure.Item[i]^.X);
    dy:=Y-VcChart.YGraphToImage(PtSourceMeasure.Item[i]^.Y);
    d:=sqrt(dx*dx+dy*dy);
    if d<r then begin
      newx:=PtSourceMeasure.Item[i]^.X;
      newy:=PtSourceMeasure.Item[i]^.Y;
      r:=d;
    end;
  end;
  if (newx>0)and(newy>0) then begin
    pointg.x:=newx;
    pointg.y:=newy;
  end;
  // show position
  LabelCoord.Caption:='Pos:'+IntToStr(trunc(pointg.x))+' HFD:'+FormatFloat(f1,pointg.y);
  except
  end;
  end else begin
    LabelCoord.Caption:='';
  end;
end;

procedure Tf_starprofile.msg(txt:string; level: integer);
begin
 if assigned(FonMsg) then FonMsg(txt,level);
end;

procedure Tf_starprofile.ClearGraph;
begin
 ProfileSource.Clear;
 HistSourceHfd.Clear;
 HistSourceImax.Clear;
end;

procedure Tf_starprofile.PlotProfile(f: TFits; bg: double; s:integer);
var i,j,i0,j0,rs:integer;
    v, valsaturation: double;
    col:TBGRAPixel;
    txt:string;
begin
if (FStarX<0)or(FStarY<0)or(s<0) then exit;
try
// labels
LabelHFD.Caption:=FormatFloat(f1,Fhfd);
LabelHistHFD.Caption:='';
for i:=1 to 3 do begin
  j:=curhist-i;
  if j>=0 then LabelHistHFD.Caption:=LabelHistHFD.Caption+' '+FormatFloat(f1,histfwhm[j]);
end;
if f.HeaderInfo.floatingpoint then
  LabelImax.Caption:=FormatFloat(f3,FValMaxCalibrated)
else
  LabelImax.Caption:=FormatFloat(f0,FValMaxCalibrated);
if Fsnr>0 then
   LabelSNR.Caption:=FormatFloat(f1,Fsnr)
else
   LabelSNR.Caption:='-';
if Ffwhm>0 then begin
  txt:=FormatFloat(f1,Ffwhm);
  if Ffwhmarcsec>0 then txt:=txt+'/'+FormatFloat(f1,Ffwhmarcsec)+'"';
  LabelFWHM.Caption:=txt;
end
else
  LabelFWHM.Caption:='-';
// Star profile
if FValMax>0 then begin
  bg:=max(bg,0);
  rs:=s div 2;
  if (FStarX-rs)<0 then rs:=round(FStarX);
  if (FStarX+rs)>(img_Width-1) then rs:=img_Width-1-integer(round(FStarX));
  if (FStarY-rs)<0 then rs:=round(FStarY);
  if (FStarY+rs)>(img_Height-1) then rs:=img_Height-1-integer(round(FStarY));
  if rs<=0 then exit;
  s:=2*rs;
  j:=trunc(FStarY);
  i0:=trunc(FStarX)-(s div 2);
  ProfileSource.Clear;
  ProfileSource.Add(0,f.image[0,j,i0]-bg);
  for i:=0 to s-1 do begin
    ProfileSource.Add(i,f.image[0,j,i0+i]-bg);
  end;
  // color profile
  if f.HeaderInfo.floatingpoint then
    valsaturation:=MaxDouble
  else
    valsaturation:=MaxADU-1-bg;
  s:=max(10,round(4*Fhfd));
  j0:=trunc(FStarY)-(s div 2);
  i0:=trunc(FStarX)-(s div 2);
  ColorImg.SetSize(s,s);
  for j:=0 to s-1 do begin
    for i:=0 to s-1 do begin
      v:=f.image[0,j0+j,i0+i]-bg;
      if v>=valsaturation then col:=VGAPurple
      else if v>=FValMax/2 then col:=VGALime
      else if v>=FValMax*0.09 then col:=VGAYellow
      else if v>=FValMax*0.03 then col:=VGARed
      else col:=BGRABlack;
      ColorImg.Canvas.Pixels[i,j]:=col;
    end;
  end;
  Star2D.Picture.Assign(ColorImg);
  Star2D.Invalidate;
end;
except
  on E: Exception do begin
    msg('PlotProfile :'+ E.Message,0);
  end;
end;
end;

procedure Tf_starprofile.PlotHistory;
var i:integer;
begin
try
if curhist>maxhist then
  for i:=0 to maxhist-1 do begin
    histfwhm[i]:=histfwhm[i+1];
    histimax[i]:=histimax[i+1];
    curhist:=maxhist;
  end;
histfwhm[curhist]:=Fhfd;
histimax[curhist]:=FValMaxCalibrated;
if histfwhm[curhist] > maxfwhm then maxfwhm:=histfwhm[curhist];
if histimax[curhist] > maximax then maximax:=histimax[curhist];
if FValMax>0 then begin
  HistSourceHfd.Clear;
  HistSourceImax.Clear;
  for i:=0 to curhist do begin
    HistSourceHfd.Add(i,histfwhm[i]);
    HistSourceImax.Add(i,histimax[i]*maxfwhm/maximax);
  end;
end;
HistoryChartHfd.Pointer.Visible:=(curhist<10);
inc(curhist);
except
  on E: Exception do begin
    msg('PlotHistory :'+ E.Message,0);
  end;
end;
end;

procedure Tf_starprofile.ShowSharpness(f: TFits);
begin
  Fhfd:=image_sharpness(f.image);
  FValMax:=f.imageMax;
  PlotHistory;
  LabelHFD.Caption:=FormatFloat(f2,Fhfd);
  LabelHistHFD.Caption:='';
  LabelImax.Caption:=FormatFloat(f0,FValMax);
  LabelFWHM.Caption:='-';
end;

procedure Tf_starprofile.ShowProfile(f: TFits; x,y,s: integer; focal:double=-1; pxsize:double=-1);
var bg,bgdev,flux: double;
  xg,yg: double;
  xm,ym,ri: integer;
begin
 if (x<0)or(y<0)or(s<0) then exit;

 try

 s:=s div 2;

 if s>=(f.HeaderInfo.naxis1 div 2) then s:=f.HeaderInfo.naxis1 div 2;
 if s>=(f.HeaderInfo.naxis2 div 2) then s:=f.HeaderInfo.naxis2 div 2;

 f.FindStarPos(x,y,s,xm,ym,ri,FValMax,bg,bgdev);
 if FValMax=0 then exit;

 f.GetHFD2(xm,ym,2*ri,xg,yg,bg,bgdev,Fhfd,Ffwhm,FValMax,Fsnr,flux);
 FValMaxCalibrated:=FValMax+bg;
 if (Ffwhm>0)and(focal>0)and(pxsize>0) then begin
   Ffwhmarcsec:=Ffwhm*3600*rad2deg*arctan(pxsize/1000/focal);
 end
 else Ffwhmarcsec:=-1;

 // Plot result
 if (Fhfd>0) then begin
   FFindStar:=true;
   FStarX:=round(xg);
   FStarY:=round(yg);
   PlotProfile(f,bg,max(s,round(3*Fhfd)));
   PlotHistory;
 end else begin
   FFindStar:=false;
   LabelHFD.Caption:='-';
   LabelHistHFD.Caption:='';
   LabelFWHM.Caption:='-';
   LabelImax.Caption:='-';
 end;
 if assigned(FonStarSelection) then FonStarSelection(self);
 except
   on E: Exception do begin
     msg('ShowProfile :'+ E.Message,0);
   end;
 end;
end;

procedure Tf_starprofile.Autofocus(f: TFits; x,y,s: integer);
var bg,bgdev,star_fwhm,focuspos,tempcomp: double;
  xg,yg,flux,med: double;
  xm,ym,ri,ns,i,nhfd: integer;
  hfdlist: array of double;
  txt:string;
begin

 // Canceling autofocus if no fits file
 if f=nil then begin
   FAutofocusResult:=false;
   ChkAutofocusDown(false);
   exit;
 end;

 bg:=0;
 if InplaceAutofocus then begin           // in place
   if AutofocusMode=afPlanet then begin   // Planet contrast
    Fhfd:=image_sharpness(f.image);
    FValMax:=f.imageMax;
    bg:=0;
    Fsnr:=100;
    Ffwhm:=-1
   end
   else begin                             // measure multiple stars
    f.MeasureStarList(s,AutofocusStarList);
    ns:=Length(f.StarList);
    if ns>0 then begin
      SetLength(hfdlist,ns);
      for i:=0 to ns-1 do
        hfdlist[i]:=f.StarList[i].hfd;
      med:=SMedian(hfdlist);             {median of stars hfd}
      s:=min(max(14,round(3.0*med)),s); {reasonable window to measure this star}
    end
    else
      s:=20; {no star found, try with small default window}
    // measure with new window
    f.MeasureStarList(s,AutofocusStarList);
    ns:=Length(f.StarList);
    if ns>0 then begin
       SetLength(hfdlist,ns);
       nhfd:=0;
       FValMax:=0;
       Fsnr:=0;
       for i:=0 to ns-1 do begin
         Fsnr:=max(Fsnr,f.StarList[i].snr);
         if f.StarList[i].vmax>FValMax then begin
            FValMax:=f.StarList[i].vmax;
            bg:=f.StarList[i].bg;
         end;
         if f.StarList[i].snr>AutofocusMinSNR then begin
            inc(nhfd);
            hfdlist[nhfd-1]:=f.StarList[i].hfd;
         end;
       end;
       SetLength(hfdlist,nhfd);
       if nhfd=0 then begin
         msg(Format(rsAutofocusCan5, [focuser.Position.Text, FormatFloat(f1, 0),
           FormatFloat(f1, FValMax), FormatFloat(f1, Fsnr)]),1);
         FAutofocusResult:=false;
         ChkAutofocusDown(false);
         exit;
       end;
       Fhfd:=SMedian(hfdlist);
       msg(Format(rsUsingMedianO, [inttostr(nhfd)]),3);
    end
    else begin
       msg(rsAutofocusCan3,0);
       FAutofocusResult:=false;
       ChkAutofocusDown(false);
       if LogToFile then begin
         txt:=slash(LogDir)+'focus_fail_'+FormatDateTime('yyyymmdd_hhnnss',now)+'.fits';
         f.SaveToFile(txt);
         msg(Format(rsSavedFile, [txt]),2);
       end;
       exit;
    end;
   end;
 end
 else begin                      // measure one star
   // Canceling autofocus if no star position given
   if (x<0)or(y<0)or(s<0) then begin
     msg(rsAutofocusCan2,0);
     FAutofocusResult:=false;
     ChkAutofocusDown(false);
     exit;
   end;
  f.FindStarPos(x,y,s,xm,ym,ri,FValMax,bg,bgdev);
  if FValMax=0 then begin
     msg(rsAutofocusCan3,0);
     FAutofocusResult:=false;
     ChkAutofocusDown(false);
     exit;
  end;
  f.GetHFD2(xm,ym,2*ri,xg,yg,bg,bgdev,Fhfd,star_fwhm,FValMax,Fsnr,flux,false);
  // process this measurement
  if (Fhfd<=0) then begin
    msg(rsAutofocusCan4,0);
    FAutofocusResult:=false;
    ChkAutofocusDown(false);
    exit;
  end;
  if (Fhfd<=0)or((not Undersampled)and(Fhfd<0.8)) then begin
    msg(Format(rsAutofocusRun, [FormatFloat(f1, Fhfd), FormatFloat(f1, FValMax+bg), FormatFloat(f1, Fsnr)]),3);
    msg(rsWeAreProbabl,0);
    msg(rsPleaseCreate,0);
    FAutofocusResult:=false;
    ChkAutofocusDown(false);
    exit;
  end;
  // sum of multiple exposures
  if (AutofocusNearNum>1)and
    (not((AutofocusVcStep=vcsCheckL)or(AutofocusVcStep=vcsCheckR)))and
    (not FirstFrame)and
    (not terminated)
    then begin
    FFindStar:=true;
    FStarX:=round(xg);
    FStarY:=round(yg);
    PlotProfile(f,bg,s);
    FhfdList[FnumHfd]:=Fhfd;
    FMinSnr:=min(FMinSnr,Fsnr);
    FminPeak:=min(FminPeak,FValMax);
    inc(FnumHfd);
    msg(Format(rsAutofocusMea, [inttostr(FnumHfd), inttostr(AutofocusNearNum),
      FormatFloat(f1, Fhfd), FormatFloat(f1, FValMax+bg), FormatFloat(f1, Fsnr)]),3);
    if FnumHfd>=AutofocusNearNum then begin  // mean of measurement
      Fhfd:=SMedian(FhfdList);
      FnumHfd:=0;
      Fsnr:=FMinSnr;
      FValMax:=FminPeak;
      FMinSnr:=99999;
      FminPeak:=999999;
    end
    else begin
      exit;
    end;
  end;
 end;
  // plot progress
  if InplaceAutofocus then begin
    LabelHFD.Caption:=FormatFloat(f1,Fhfd);
    LabelHistHFD.Caption:='';
    if FValMax>1 then
       LabelImax.Caption:=FormatFloat(f0,FValMax+bg)
    else
       LabelImax.Caption:=FormatFloat(f3,FValMax+bg);
    if Ffwhm>0 then begin
      txt:=FormatFloat(f1,Ffwhm);
      if Ffwhmarcsec>0 then txt:=txt+'/'+FormatFloat(f1,Ffwhmarcsec)+'"';
      LabelFWHM.Caption:=txt;
    end
    else
      LabelFWHM.Caption:='-';
    if assigned(FonStarSelection) then FonStarSelection(self);
  end
  else begin
    FFindStar:=true;
    FStarX:=round(xg);
    FStarY:=round(yg);
    Ffwhm:=-1;
    PlotProfile(f,bg,s);
    if assigned(FonStarSelection) then FonStarSelection(self);
  end;
  if not FirstFrame then begin
    inc(FnumGraph);
    if AutofocusMode=afVcurve then begin
      PtSourceMeasure.Add(focuser.FocusPosition,Fhfd,'',colorGreen);
    end
    else if (AutofocusMode=afDynamic)or(AutofocusMode=afPlanet) then begin
    if (not terminated) then begin
      if DynAbsStartPos>0 then
        i:=DynAbsStartPos+(FnumGraph-1)*DynAbsStep
      else
        i:=FnumGraph;
      if (FValMax+bg)< (0.9995*ClippingOverflow) then
         PtSourceMeasure.Add(i,Fhfd,'',colorBlue)
      else
         PtSourceMeasure.Add(i,Fhfd,'',colorRed);
      FitSourceMeasure.Add(i,Fhfd);
    end;
    end
    else
    if (not terminated) then begin
      PtSourceMeasure.Add(FnumGraph,Fhfd,'',colorGreen);
      FitSourceMeasure.Add(FnumGraph,Fhfd);
    end;
  end;
  // check low snr
  if fsnr<AutofocusMinSNR then begin
    msg(Format(rsAutofocusCan5, [focuser.Position.Text, FormatFloat(f1, Fhfd),
      FormatFloat(f1, FValMax), FormatFloat(f1, Fsnr)]),1);
    FAutofocusResult:=false;
    ChkAutofocusDown(false);
    exit;
  end;
  // check focus result
  if terminated then begin
    if (Fhfd<=AutofocusTolerance) or (AutofocusMode=afPlanet) then FAutofocusResult:=true;
    txt:=Format(rsAutofocusFin, [focuser.Position.Text, FormatFloat(f1, Fhfd),FormatFloat(f1, FValMax+bg), FormatFloat(f1, Fsnr), FormatFloat(f1,TempDisplay(TemperatureScale,FocuserTemp))+TempLabel]);
    if FAutofocusResult then begin
      if FPreFocusPos>0 then
         txt:=txt+' POS_DELTA:'+IntToStr(focuser.Position.Value-FPreFocusPos);
      if AutofocusLastTemp<>NullCoord then
         txt:=txt+' TEMP_DELTA:'+FormatFloat(f1,FocuserTemp-AutofocusLastTemp);
      AutofocusLastTemp:=FocuserTemp;
    end
    else txt:=txt+' '+rsAutoFocusErr;
    msg(txt,2);
    AutoFocusLastTime:=now;
    if FAutofocusResult then begin
      FAutofocusDone:=true;
      LastFocusMsg:=rsAutoFocusSuc+crlf+FormatDateTime('hh:nn:ss', now)+' HFD='+FormatFloat(f1, Fhfd);
      // adjust slippage offset with current result
      if AutofocusSlippageCorrection and (AutofocusMode=afVcurve) then begin
        if AutofocusVcTemp<>NullCoord then
           tempcomp:=focuser.TempOffset(AutofocusVcTemp,FocuserTemp)
        else
           tempcomp:=0;
        focuspos:=focuser.FocusPosition;
        focuspos:=focuspos-(CurrentFilterOffset-AutofocusVcFilterOffset);
        focuspos:=focuspos-tempcomp;
        AutofocusSlippageOffset:=round(focuspos-(AutofocusVcpiL+AutofocusVcpiR)/2);
        config.SetValue('/StarAnalysis/AutofocusSlippageOffset',AutofocusSlippageOffset);
        msg(Format(rsFocuserSlipp, [inttostr(AutofocusSlippageOffset)]),3);
      end;
    end
    else begin
       LastFocusMsg:=rsAutofocusFai+crlf+FormatDateTime('hh:nn:ss', now);
       msg(Format(rsAutofocusFin2, [FormatFloat(f1, AutofocusTolerance)]),0);
    end;
    LastFocusimage.SetSize(VcChart.Width,VcChart.Height);
    VcChart.PaintTo(LastFocusimage.Canvas,0,0);
    ChkAutofocusDown(false);
    exit;
  end;
  FirstFrame:=false;
  msg(Format(rsAutofocusRun, [FormatFloat(f1, Fhfd), FormatFloat(f1, FValMax+bg), FormatFloat(f1, Fsnr)]),3);
  // do focus and continue
  case AutofocusMode of
    afVcurve   : doAutofocusVcurve;
    afDynamic  : doAutofocusDynamic;
    afIterative: doAutofocusIterative;
    afPlanet   : doAutofocusPlanet;
  end;
end;

procedure Tf_starprofile.doAutofocusVcurve;
var newpos,delta,meanhfd,tempcomp:double;
begin
 if not ChkAutofocus.Down then exit;
 case AutofocusVcStep of
   vcsStartL: begin
              // temperature compensation
              if AutofocusVcTemp<>NullCoord then
                 tempcomp:=focuser.TempOffset(AutofocusVcTemp,FocuserTemp)
              else
                 tempcomp:=0;
              // move to start focus position
              newpos:=AutofocusVcpiL+(AutofocusStartHFD/AutofocusVcSlopeL);
              if newpos<AutofocusVc[0,1] then begin
                 msg(rsStartFocusHF,0);
                 ChkAutofocusDown(false);
                 exit;
              end;
              // correct for filter offset
              newpos:=newpos+(CurrentFilterOffset-AutofocusVcFilterOffset);
              // correct for temperature
              newpos:=newpos+tempcomp;
              // correct for slippage
              if AutofocusSlippageCorrection then newpos:=newpos+AutofocusSlippageOffset;
              focuser.FocusPosition:=round(newpos);
              msg(Format(rsAutofocusMov, [focuser.Position.Text]),3);
              FonAbsolutePosition(self);
              AutofocusVcStep:=vcsNearL;
              wait(1);
             end;
   vcsStartR: begin
              // temperature compensation
              if AutofocusVcTemp<>NullCoord then
                 tempcomp:=focuser.TempOffset(AutofocusVcTemp,FocuserTemp)
              else
                 tempcomp:=0;
              // move to start focus position
              newpos:=AutofocusVcpiR+(AutofocusStartHFD/AutofocusVcSlopeR);
              if newpos>AutofocusVc[AutofocusVcNum,1] then begin
                 msg(rsStartFocusHF,0);
                 ChkAutofocusDown(false);
                 exit;
              end;
              // correct for filter offset
              newpos:=newpos+(CurrentFilterOffset-AutofocusVcFilterOffset);
              // correct for temperature
              newpos:=newpos+tempcomp;
              // correct for slippage
              if AutofocusSlippageCorrection then newpos:=newpos+AutofocusSlippageOffset;
              focuser.FocusPosition:=round(newpos);
              msg(Format(rsAutofocusMov, [focuser.Position.Text]),3);
              FonAbsolutePosition(self);
              AutofocusVcStep:=vcsNearR;
              wait(1);
             end;
   vcsNearL: begin
              // compute near focus position
              delta:=(AutofocusStartHFD-Fhfd)/AutofocusVcSlopeL;
              newpos:=AutofocusVcpiL+(AutofocusNearHFD/AutofocusVcSlopeL)+delta;
              // correct for filter offset
              newpos:=newpos+(CurrentFilterOffset-AutofocusVcFilterOffset);
              // correct for temperature
              newpos:=newpos+tempcomp;
              // correct for slippage
              if AutofocusSlippageCorrection then newpos:=newpos+AutofocusSlippageOffset;
              // move to near focus position
              focuser.FocusPosition:=round(newpos);
              msg(Format(rsAutofocusMov2, [focuser.Position.Text]),3);
              FonAbsolutePosition(self);
              AutofocusVcStep:=vcsCheckL;
              AutofocusVcCheckNum:=0;
              SetLength(AutofocusVcCheckHFDlist,0);
              wait(1);
             end;
   vcsNearR: begin
              // compute near focus position
              delta:=(AutofocusStartHFD-Fhfd)/AutofocusVcSlopeR;
              newpos:=AutofocusVcpiR+(AutofocusNearHFD/AutofocusVcSlopeR)+delta;
              // correct for filter offset
              newpos:=newpos+(CurrentFilterOffset-AutofocusVcFilterOffset);
              // correct for temperature
              newpos:=newpos+tempcomp;
              // correct for slippage
              if AutofocusSlippageCorrection then newpos:=newpos+AutofocusSlippageOffset;
              // move to near focus position
              focuser.FocusPosition:=round(newpos);
              msg(Format(rsAutofocusMov2, [focuser.Position.Text]),3);
              FonAbsolutePosition(self);
              AutofocusVcStep:=vcsCheckR;
              AutofocusVcCheckNum:=0;
              SetLength(AutofocusVcCheckHFDlist,0);
              wait(1);
             end;
   vcsCheckL:begin
              inc(AutofocusVcCheckNum);
              dec(FnumGraph);
              SetLength(AutofocusVcCheckHFDlist,AutofocusVcCheckNum);
              AutofocusVcCheckHFDlist[AutofocusVcCheckNum-1]:=Fhfd;
              meanhfd:=SMedian(AutofocusVcCheckHFDlist);
              newpos:=focuser.FocusPosition-(meanhfd/AutofocusVcSlopeL)+AutofocusVcPID/2;
              msg(Format(rsAutofocusMea2, [IntToStr(AutofocusVcCheckNum),
                FormatFloat(f3, meanhfd), IntToStr(round(newpos))]),3);
              if AutofocusVcCheckNum>=AutofocusNearNum then begin
                AutofocusVcStep:=vcsFocusL;
                doAutofocusVcurve;
              end;
             end;
   vcsCheckR:begin
              inc(AutofocusVcCheckNum);
              dec(FnumGraph);
              SetLength(AutofocusVcCheckHFDlist,AutofocusVcCheckNum);
              AutofocusVcCheckHFDlist[AutofocusVcCheckNum-1]:=Fhfd;
              meanhfd:=SMedian(AutofocusVcCheckHFDlist);
              newpos:=focuser.FocusPosition-(meanhfd/AutofocusVcSlopeR)-AutofocusVcPID/2;
              msg(Format(rsAutofocusMea2, [IntToStr(AutofocusVcCheckNum),
                FormatFloat(f3, meanhfd), IntToStr(round(newpos))]),3);
              if AutofocusVcCheckNum>=AutofocusNearNum then begin
                AutofocusVcStep:=vcsFocusR;
                doAutofocusVcurve;
              end;
             end;
   vcsFocusL:begin
              // move to focus
              inc(FnumGraph);
              meanhfd:=SMedian(AutofocusVcCheckHFDlist);
              newpos:=focuser.FocusPosition-(meanhfd/AutofocusVcSlopeL)+AutofocusVcPID/2;
              focuser.FocusPosition:=round(newpos);
              msg(Format(rsAutofocusMov3, [focuser.Position.Text]),3);
              FonAbsolutePosition(self);
              terminated:=true;
              wait(1);
             end;
   vcsFocusR:begin
              // move to focus
              inc(FnumGraph);
              meanhfd:=SMedian(AutofocusVcCheckHFDlist);
              newpos:=focuser.FocusPosition-(meanhfd/AutofocusVcSlopeR)-AutofocusVcPID/2;
              focuser.FocusPosition:=round(newpos);
              msg(Format(rsAutofocusMov3, [focuser.Position.Text]),3);
              FonAbsolutePosition(self);
              terminated:=true;
              wait(1);
             end;
 end;
end;

procedure Tf_starprofile.doAutofocusDynamic;
var i,k,step,sumpos,numpos: integer;
    p_hyp,a_hyp,b_hyp,x: double;
  procedure ResetPos;
  begin
    k:=round(AutofocusDynamicMovement*(AutofocusDynamicNumPoint-aminpos));
    if k>0 then begin
      focuser.FocusSpeed:=k;
      if AutofocusMoveDir=FocusDirIn then begin
        onFocusOUT(self);
      end
      else begin
        onFocusIN(self);
      end;
      Wait(1);
    end;
  end;
begin
  case AutofocusDynamicStep of
    afdStart: begin
              if not odd(AutofocusDynamicNumPoint) then
                inc(AutofocusDynamicNumPoint);
              if AutofocusDynamicNumPoint<5 then AutofocusDynamicNumPoint:=5;
              SetLength(dyn_v_curve,AutofocusDynamicNumPoint+1);
              // set initial position
              DynAbsStartPos:=focuser.FocusPosition;  //return -1 for relative focuser
              k:=AutofocusDynamicNumPoint div 2;
              focuser.FocusSpeed:=AutofocusDynamicMovement*k;
              if AutofocusMoveDir=FocusDirIn then begin
                onFocusOUT(self);
                if DynAbsStartPos>0 then DynAbsStartPos:=DynAbsStartPos+AutofocusDynamicMovement*k;
                DynAbsStep:=-AutofocusDynamicMovement;
              end
              else begin
                onFocusIN(self);
                if DynAbsStartPos>0 then DynAbsStartPos:=DynAbsStartPos-AutofocusDynamicMovement*k;
                DynAbsStep:=AutofocusDynamicMovement;
              end;
              afmpos:=0;
              aminhfd:=9999;
              amaxhfd:=-1;
              focuser.FocusSpeed:=AutofocusDynamicMovement;
              AutofocusDynamicStep:=afdMeasure;
              end;
    afdMeasure: begin
              // store hfd
              inc(afmpos);
              dyn_v_curve[afmpos-1,1]:=afmpos; // measurement number, to work with relative position focuser
              dyn_v_curve[afmpos-1,2]:=Fhfd;
              if Fhfd<aminhfd then begin
                aminhfd:=Fhfd;
              end;
              if Fhfd>amaxhfd then begin
                amaxhfd:=Fhfd;
              end;
              if afmpos=(AutofocusDynamicNumPoint) then begin
                // last point, process measurements
                AutofocusDynamicStep:=afdEnd;
                doAutofocusDynamic;
                exit
              end;
              // increment position
              if AutofocusMoveDir=FocusDirIn then
                onFocusIN(self)
              else
                onFocusOUT(self);
              end;
    afdEnd: begin
              sumpos:=0;
              numpos:=0;
              // find position with minimum measured HFD
              for i:=0 to AutofocusDynamicNumPoint-1 do begin
                if abs(aminhfd-dyn_v_curve[i,2])<(0.1*aminhfd) then begin
                 inc(numpos);
                 sumpos:=sumpos+i+1;
                end;
              end;
              aminpos:=round(sumpos/numpos);
              // check measure validity
              if (aminpos<2)or((AutofocusDynamicNumPoint-aminpos)<2) then begin
                 // not enough point on one side
                 ResetPos;
                 if FAutofocusRestart>0 then begin
                   // we already retry, abort now
                   msg(rsNotEnoughPoi,0);
                   msg(rsTheFocuserIs,1);
                   terminated:=true;
                 end
                 else begin
                   // retry using new position
                   msg(rsNotEnoughPoi2,2);
                   InitAutofocus(true);
                   AutofocusDynamicStep:=afdStart;
                 end;
                 exit;
              end;
              if (amaxhfd<(1.5*aminhfd)) then begin
                 // not enough difference between min and max HFD, abort
                 msg(rsTooSmallHFDD,0);
                 msg(rsTheFocuserIs,1);
                 ResetPos;
                 terminated:=true;
                 exit;
              end;
              // compute focus
              p_hyp:=0;a_hyp:=0;b_hyp:=0;
              find_best_hyperbola_fit(dyn_v_curve,afmpos,p_hyp,a_hyp,b_hyp); {output: bestfocusposition=p, a, b of hyperbola}
              if DynAbsStartPos>0 then
                x:=DynAbsStartPos+(p_hyp-1)*DynAbsStep
              else
                x:=p_hyp;
              msg(Format(rsHYPERBOLACur, [FormatFloat(f3, x), FormatFloat(f4, lowest_error), inttostr(iteration_cycles)]),3 );
              if DynAbsStartPos>0 then
                PtSourceComp.Add(DynAbsStartPos+(p_hyp-1)*DynAbsStep,a_hyp,'',clFuchsia)
              else
                PtSourceComp.Add(p_hyp,a_hyp,'',clFuchsia);
              for i:=10 to 10*FnumGraph do begin
                if DynAbsStartPos>0 then
                  x:=DynAbsStartPos+((i/10)-1)*DynAbsStep
                else
                  x:=i/10;
                FitSourceComp.Add(x,hfd_calc(i/10,p_hyp,a_hyp,b_hyp));
              end;
              // focus position with last move in focus direction
              step:=round(AutofocusDynamicMovement*(AutofocusDynamicNumPoint-p_hyp)); //require steps from current position at the end of the curve
              if focuser.BacklashActive then begin
                focuser.FocusSpeed:=step;
                 if AutofocusMoveDir=FocusDirIn then begin
                   onFocusOUT(self);  // wrong direction but compensated by backlash correction
                 end
                 else begin
                   onFocusIN(self);   // wrong direction but compensated by backlash correction
                 end;
              end
              else begin
                focuser.FocusSpeed:=step+AutofocusDynamicMovement;  // move a bit more
                if AutofocusMoveDir=FocusDirIn then begin
                  onFocusOUT(self);
                  wait; // let time for position refresh
                  focuser.FocusSpeed:=AutofocusDynamicMovement;     // got to position in right direction
                  onFocusIN(self);
                end
                else begin
                  onFocusIN(self);
                  wait; // let time for position refresh
                  focuser.FocusSpeed:=AutofocusDynamicMovement;     // got to position in right direction
                  onFocusOUT(self)
                end;
              end;
              terminated:=true;
              end;
  end;
end;

procedure Tf_starprofile.doAutofocusPlanet;
var i,k,step,sumpos,numpos: integer;
    p_hyp,a_hyp,b_hyp,x: double;
  procedure ResetPos;
  begin
    k:=round(AutofocusPlanetMovement*(AutofocusPlanetNumPoint-aminpos));
    if k>0 then begin
      focuser.FocusSpeed:=k;
      if AutofocusMoveDir=FocusDirIn then begin
        onFocusOUT(self);
      end
      else begin
        onFocusIN(self);
      end;
      Wait(1);
    end;
  end;
begin
  case AutofocusPlanetStep of
    afpStart: begin
              if not odd(AutofocusPlanetNumPoint) then
                inc(AutofocusPlanetNumPoint);
              if AutofocusPlanetNumPoint<5 then AutofocusPlanetNumPoint:=5;
              SetLength(dyn_v_curve,AutofocusPlanetNumPoint+1);
              // set initial position
              DynAbsStartPos:=focuser.FocusPosition;  //return -1 for relative focuser
              k:=AutofocusPlanetNumPoint div 2;
              focuser.FocusSpeed:=AutofocusPlanetMovement*k;
              if AutofocusMoveDir=FocusDirIn then begin
                onFocusOUT(self);
                if DynAbsStartPos>0 then DynAbsStartPos:=DynAbsStartPos+AutofocusPlanetMovement*k;
                DynAbsStep:=-AutofocusPlanetMovement;
              end
              else begin
                onFocusIN(self);
                if DynAbsStartPos>0 then DynAbsStartPos:=DynAbsStartPos-AutofocusPlanetMovement*k;
                DynAbsStep:=AutofocusPlanetMovement;
              end;
              afmpos:=0;
              aminhfd:=9999;
              amaxhfd:=-1;
              focuser.FocusSpeed:=AutofocusPlanetMovement;
              AutofocusPlanetStep:=afpMeasure;
              end;
    afpMeasure: begin
              // store hfd
              inc(afmpos);
              dyn_v_curve[afmpos-1,1]:=afmpos; // measurement number, to work with relative position focuser
              dyn_v_curve[afmpos-1,2]:=Fhfd;
              if Fhfd<aminhfd then begin
                aminhfd:=Fhfd;
              end;
              if Fhfd>amaxhfd then begin
                amaxhfd:=Fhfd;
              end;
              if afmpos=(AutofocusPlanetNumPoint) then begin
                // last point, process measurements
                AutofocusPlanetStep:=afpEnd;
                doAutofocusPlanet;
                exit
              end;
              // increment position
              if AutofocusMoveDir=FocusDirIn then
                onFocusIN(self)
              else
                onFocusOUT(self);
              end;
    afpEnd: begin
              sumpos:=0;
              numpos:=0;
              // find position with minimum measured HFD
              for i:=0 to AutofocusPlanetNumPoint-1 do begin
                if abs(aminhfd-dyn_v_curve[i,2])<(0.1*aminhfd) then begin
                 inc(numpos);
                 sumpos:=sumpos+i+1;
                end;
              end;
              aminpos:=round(sumpos/numpos);
              // check measure validity
              if (aminpos<2)or((AutofocusPlanetNumPoint-aminpos)<2) then begin
                 // not enough point on one side
                 ResetPos;
                 if FAutofocusRestart>0 then begin
                   // we already retry, abort now
                   msg(rsNotEnoughPoi,0);
                   msg(rsTheFocuserIs,1);
                   terminated:=true;
                 end
                 else begin
                   // retry using new position
                   msg(rsNotEnoughPoi2,2);
                   InitAutofocus(true);
                   AutofocusDynamicStep:=afdStart;
                 end;
                 exit;
              end;
              // compute focus
              p_hyp:=0;a_hyp:=0;b_hyp:=0;
              find_best_hyperbola_fit(dyn_v_curve,afmpos,p_hyp,a_hyp,b_hyp); {output: bestfocusposition=p, a, b of hyperbola}
              if DynAbsStartPos>0 then
                x:=DynAbsStartPos+(p_hyp-1)*DynAbsStep
              else
                x:=p_hyp;
              msg(Format(rsHYPERBOLACur, [FormatFloat(f3, x), FormatFloat(f4, lowest_error), inttostr(iteration_cycles)]),3 );
              if DynAbsStartPos>0 then
                PtSourceComp.Add(DynAbsStartPos+(p_hyp-1)*DynAbsStep,a_hyp,'',clFuchsia)
              else
                PtSourceComp.Add(p_hyp,a_hyp,'',clFuchsia);
              for i:=10 to 10*FnumGraph do begin
                if DynAbsStartPos>0 then
                  x:=DynAbsStartPos+((i/10)-1)*DynAbsStep
                else
                  x:=i/10;
                FitSourceComp.Add(x,hfd_calc(i/10,p_hyp,a_hyp,b_hyp));
              end;
              // focus position with last move in focus direction
              step:=round(AutofocusPlanetMovement*(AutofocusPlanetNumPoint-p_hyp)); //require steps from current position at the end of the curve
              if focuser.BacklashActive then begin
                focuser.FocusSpeed:=step;
                 if AutofocusMoveDir=FocusDirIn then begin
                   onFocusOUT(self);  // wrong direction but compensated by backlash correction
                 end
                 else begin
                   onFocusIN(self);   // wrong direction but compensated by backlash correction
                 end;
              end
              else begin
                focuser.FocusSpeed:=step+AutofocusPlanetMovement;  // move a bit more
                if AutofocusMoveDir=FocusDirIn then begin
                  onFocusOUT(self);
                  focuser.FocusSpeed:=AutofocusPlanetMovement;     // got to position in right direction
                  onFocusIN(self);
                end
                else begin
                  onFocusIN(self);
                  focuser.FocusSpeed:=AutofocusPlanetMovement;     // got to position in right direction
                  onFocusOUT(self)
                end;
              end;
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
      FfocuserSpeed:=max(FfocuserSpeed div 2,AutofocusMinSpeed);   // divide speed by 2
      focuser.FocusSpeed:=FfocuserSpeed; // set new speed
      focuserdirection:=not focuserdirection;
    end;
  end;
  if focuserdirection=FocusDirIn
     then begin
        msg(Format(rsAutofocusFoc, [inttostr(FfocuserSpeed)]),3);
        FonFocusIN(self);
      end
     else begin
       msg(Format(rsAutofocusFoc2, [inttostr(FfocuserSpeed)]),3);
       FonFocusOUT(self);
     end;
  FLastHfd:=Fhfd;
end;

end.


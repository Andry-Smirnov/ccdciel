unit cu_autoguider_internal;

{$mode objfpc}{$H+}

{
Copyright (C) 2022 Patrick Chevalley & Han Kleijn

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

uses cu_autoguider, u_global, u_utils, math, fu_internalguider, indiapi,
  u_translation, Graphics, Forms, Classes, SysUtils;

type
  star_position=record x1,y1,x2,y2,flux: double; end;//for internal guider
  star_position_array= array of star_position;//for internal guider


  T_autoguider_internal = class(T_autoguider)
  private
    InternalguiderInitialize,InternalCalibrationInitialize,GuideLogFileOpen : boolean;
    pulseRA,pulseDEC,GuideFrameCount, InternalguiderCalibrationDirection,InternalguiderCalibrationStep,
    CalibrationDuration,Calflip,CalCount,Calnrtest           : integer;
    driftX,driftY,driftRA,driftDec,moveRA,moveDEC, Guidethecos,old_moveRA,old_moveDEC,  paEast, paNorth,
    pulsegainEast,pulsegainWest,pulsegainNorth,pulsegainSouth,Calthecos, Caltheangle,CaldriftOld,
    GuideStartTime,LogSNR,LogFlux,mean_hfd,ditherX,ditherY : double;
    xy_trend : xy_guiderlist;{fu_internalguider}
    xy_array,xy_array_old : star_position_array;//internal guider for measure drift
    GuideLog: TextFile;
    FPaused, FSettling, FSettlingInRange: boolean;
    FSettleStartTime, FSettleTime: double;
    function  measure_drift(var initialize: boolean; out drX,drY :double) : integer;
    Procedure StartGuideExposure;
    procedure InternalguiderStartAsync(Data: PtrInt);
    function  WaitPulseGuiding(pulse:longint): boolean;
    procedure SetStatus(aStatus: string ; aState: TAutoguiderState);
    Procedure InitLog;
    Procedure WriteLog( buf : string);
    Procedure CloseLog;
  protected
    Procedure ProcessEvent(txt:string); override;
    procedure Execute; override;
    procedure Terminate;
    procedure StarLostTimerTimer(Sender: TObject); override;
    procedure StartSettle;
  public
    Constructor Create;
    Destructor Destroy; override;
    Procedure Connect(cp1: string; cp2:string=''; cp3:string=''; cb1:boolean=False); override;
    procedure Disconnect; override;
    procedure Shutdown; override;
    procedure ConnectGear; override;
    procedure SettleTolerance(pixel:double; mintime,maxtime: integer); override;
    procedure Calibrate; override;
    procedure Guide(onoff:boolean; recalibrate:boolean=false); override;
    procedure Pause(onoff:boolean; settle:boolean=true); override;
    procedure Dither(pixel:double; raonly:boolean; waittime:double); override;
    procedure InternalguiderLoop;
    procedure InternalguiderStart;
    procedure InternalguiderStop;
    procedure InternalguiderCalibrate;
    procedure InternalAutoguiding;
    procedure InternalCalibration;
    procedure InternalguiderCaptureDark;
    Procedure StartGuideExposureAsync(Data: PtrInt);
    function WaitBusy(maxwait:integer=5):boolean; override;
    function WaitGuiding(maxwait:integer=5):boolean; override;
    function WaitDithering(maxwait:integer=5):boolean; override;
  end;

implementation

const
   nrpointsTrend=50; //number of trend points plotted
   max_duration=2500;//max duration guide puls in milliseconds

procedure mad_median(list: array of double;leng :integer;out mad,median :double);{calculate mad and median without modifying the data}
var  {idea from https://eurekastatistics.com/using-the-median-absolute-deviation-to-find-outliers/}
  i        : integer;
  list2: array of double;
begin
  setlength(list2,leng);
  for i:=0 to leng-1 do list2[i]:=list[i];{copy magn offset data}
  median:=Smedian(list2,leng);
  for i:=0 to leng-1 do list2[i]:=abs(list[i] - median);{fill list2 with offsets}
  mad:=Smedian(list2,leng); //median absolute deviation (MAD)
  list2:=nil;
end;


procedure get_best_mean(list: array of double; leng : integer; out mean : double);{Remove outliers from polulation using MAD. }
var  {idea from https://eurekastatistics.com/using-the-median-absolute-deviation-to-find-outliers/}
  i,count         : integer;
  median, mad     : double;

begin
 if leng=1 then begin mean:=list[0];exit end
 else
 if leng=2 then begin mean:=(list[0]+list[1])/2;exit end;
 mad_median(list,leng,mad,median);{calculate mad and median without modifying the data}
 count:=0;
 mean:=0;
 for i:=0 to leng-1 do
   if abs(list[i]-median)<1.50*1.4826*mad then {offset less the 1.5*sigma.}
   begin
     mean:=mean+list[i];{Calculate mean. This gives a little less noise then calculating median again. Note weighted mean gives poorer result and is not applied.}
     inc(count);
   end;
 if count>0 then  mean:=mean/count;  {mean without using outliers}
end;


procedure rotate2(rot,x,y :double;out  x2,y2:double);{rotate a vector point CCW}
var
  sin_rot, cos_rot :double;
begin
  sincos(rot, sin_rot, cos_rot);
  x2:=x * cos_rot - y*sin_rot;
  y2:=x * sin_rot + y*cos_rot;
end;

Constructor T_autoguider_internal.Create ;
begin
  inherited Create;
  FAutoguiderType:=agINTERNAL;
  FStatus:=rsInternal;
  FState:=GUIDER_IDLE;
  FRunning:=true;
  FPaused:=false;
  FSettling:=false;
  FSettlePix:=1;
  FSettleTmin:=5;
  FSettleTmax:=30;
  InitLog;
  StopInternalguider:=true;
  InternalguiderRunning:=false;
  InternalguiderGuiding:=false;
  InternalguiderCalibrating:=false;
  InternalguiderCapturingDark:=false;
end;

Destructor T_autoguider_internal.Destroy;
begin
  CloseLog;
  inherited Destroy;
end;

Procedure T_autoguider_internal.Connect(cp1: string; cp2:string=''; cp3:string=''; cb1:boolean=False);
begin
  // this not use the thread, connect() is called only to destroy
  start;
end;

procedure T_autoguider_internal.Disconnect;
begin
  // Not used
end;

procedure T_autoguider_internal.Execute;
begin
  // this not use the thread, just exit to destroy
end;

procedure T_autoguider_internal.Terminate;
begin
  // destroy
  Free;
end;

Procedure T_autoguider_internal.ProcessEvent(txt:string);
begin
  // event from thread, not used
end;

procedure T_autoguider_internal.ConnectGear;
begin
  // Not used
end;

procedure T_autoguider_internal.Shutdown;
begin
  // Not used
end;

procedure T_autoguider_internal.SettleTolerance(pixel:double; mintime,maxtime: integer);
begin
  FSettlePix:=pixel;
  FSettleTmin:=mintime;
  FSettleTmax:=maxtime;
end;

function T_autoguider_internal.WaitBusy(maxwait:integer=5):boolean;
var endt: TDateTime;
begin
result:=false;
try
  endt:=now+maxwait/secperday;
  while now<endt do begin
    Sleep(100);
    if GetCurrentThreadId=MainThreadID then Application.ProcessMessages;
    if terminated then break;
    if CancelAutofocus then break;
    if FStopGuiding or StopInternalguider then break;
    if FState<>GUIDER_BUSY then break;
  end;
  result:=(FState<>GUIDER_BUSY) or FStopGuiding;
except
end;
end;

function T_autoguider_internal.WaitGuiding(maxwait:integer=5):boolean;
var endt: TDateTime;
    n: integer;
begin
result:=false;
try
  endt:=now+maxwait/secperday;
  n:=0;
  while now<endt do begin
    Sleep(100);
    if GetCurrentThreadId=MainThreadID then Application.ProcessMessages;
    if terminated then break;
    if CancelAutofocus then break;
    if FStopGuiding or StopInternalguider then break;
    if FState=GUIDER_GUIDING then break;
    inc(n);
    if ((n mod 150)=0) and assigned(FonShowMessage) then
        FonShowMessage('Waiting for autoguider to start...');
  end;
  result:=(FState=GUIDER_GUIDING);
except
end;
end;

function T_autoguider_internal.WaitDithering(maxwait:integer=5):boolean;
begin
  { #todo : dither }
  result:=true;
end;

procedure T_autoguider_internal.Calibrate;
begin
  Guide(true,true);
end;

procedure T_autoguider_internal.Guide(onoff:boolean; recalibrate:boolean=false);
begin
  if onoff then begin
    if recalibrate then InternalguiderCalibrate;
    InternalguiderStart;
  end
  else begin
     InternalguiderStop;
  end;
end;

procedure T_autoguider_internal.StartSettle;
begin
  if InternalguiderGuiding then begin
    FSettling:=true;
    FSettlingInRange:=false;
    FSettleTime:=MaxDouble;
    FSettleStartTime:=now;
    SetStatus('Settling',GUIDER_BUSY);
    WriteLog('INFO: SETTLING STATE CHANGE, Settling started');
    WaitGuiding(FSettleTmax+5);
  end;
end;

procedure T_autoguider_internal.Pause(onoff:boolean; settle:boolean=true);
begin
  if onoff then begin
    if FState=GUIDER_GUIDING then begin
      FPaused:=true;
      SetStatus('Paused',GUIDER_IDLE);
      WriteLog('INFO: Server received PAUSE');

    end;
  end else begin
    FPaused:=false;
    if InternalguiderGuiding then begin
      WriteLog('INFO: Server received RESUME');
      StartSettle;
    end;
  end;
end;

procedure T_autoguider_internal.Dither(pixel:double; raonly:boolean; waittime:double);
var d,dra,ddec,mflipcorr: double;
    i: integer;
begin
  if InternalguiderGuiding and (not InternalguiderInitialize) then begin
    dra:=(2*random-1)*pixel; // in pixel
    if raonly then
      ddec:=0
    else
      ddec:=(2*random-1)*pixel;
    if (mount.PierSide=pierWest) <> (pos('E',finternalguider.pier_side)>0) then // Did a meridian flip occur since calibration.
      mflipcorr:=180 // A meridian flip occurred
    else
      mflipcorr:=0;
    rotate2(((finternalguider.PA+mflipcorr)*pi/180),dra,ddec, ditherX,ditherY);{rotate a vector point, counter clockwise}
    WriteLog('INFO: DITHER by '+FormatFloat(f3,ditherX)+', '+FormatFloat(f3,ditherY));
    StartSettle;
  end;
end;

procedure T_autoguider_internal.StarLostTimerTimer(Sender: TObject);
begin
  { #todo : star lost }
end;

procedure T_autoguider_internal.SetStatus(aStatus: string ; aState: TAutoguiderState);
begin
  FStatus:=aStatus;
  FState:=aState;
  if assigned(FonStatusChange) then FonStatusChange(self);
end;

Procedure T_autoguider_internal.InitLog;
begin
  try
     Filemode:=2;
     AssignFile(GuideLog,slash(LogDir)+'CCDciel_GuideLog_'+FormatDateTime('yyyy-mm-dd_hhnnss',now)+'.txt');
     Rewrite(GuideLog);
     WriteLn(GuideLog,'CCDciel '+ccdciel_version+'-'+RevisionStr+', Log version 2.5. Log enabled at '+FormatDateTime('YYYY-MM-DD HH:NN:SS',now));
     WriteLn(GuideLog, '');
     Flush(GuideLog);
     GuideLogFileOpen:=true;
  except
  {$I-}
     GuideLogFileOpen:=false;
     CloseFile(GuideLog);
     IOResult;
  {$I+}
  end;
end;

Procedure T_autoguider_internal.CloseLog;
begin
  try
    if GuideLogFileOpen then begin
      WriteLn(GuideLog,'Log closed at '+FormatDateTime('YYYY-MM-DD HH:NN:SS',now));
      GuideLogFileOpen:=false;
      CloseFile(GuideLog);
    end;
  except
    {$I-}
    IOResult;
    {$I+}
  end;
end;

Procedure T_autoguider_internal.WriteLog( buf : string);
begin
  try
     if GuideLogFileOpen then begin
       WriteLn(GuideLog,buf);
       Flush(GuideLog);
     end;
  except
    {$I-}
    on E: Exception do begin
      GuideLogFileOpen:=false;
      msg('Error writing guide log file: '+ E.Message,1);
      CloseFile(GuideLog);
    end;
    {$I+}
  end;
end;

function  T_autoguider_internal.measure_drift(var initialize:boolean; out drX,drY :double) : integer;// ReferenceX,Y indicates the total drift, drX,drY to drift since previouse call. Arrays old_xy_array,xy_array are for storage star positions
var
  i,j,m,n,fitsx,fitsy,stepsize,xsize,ysize,star_counter,counter,r, rxc,ryc,len,nrtokeep,index,match_counter: integer;
  hfd1,star_fwhm,vmax,bg,bgdev,xc,yc,snr,flux,fluxratio,flux_min,v,value,min_SNR,min_HFD  : double;
  drift_arrayX,drift_arrayY : array of double;
const
    searchA=28;//square search area
    overlap=6;
    maxstars=1000;
begin
  result:=1;// Assume no stars detected
  star_counter:=0;
  stepsize:=searchA-overlap;//some overlap

  // for guide log
  LogSNR:=0;
  LogFlux:=0;

  FGuideBmp.Canvas.Pen.Color:=clYellow;
  FGuideBmp.Canvas.Pen.Mode:=pmMerge;
  FGuideBmp.Canvas.Pen.Style:=psSolid;
  FGuideBmp.Canvas.Pen.Width:=1;

  xsize:=guidefits.HeaderInfo.naxis1;// width image
  ysize:=guidefits.HeaderInfo.naxis2;// height image

  if initialize then
  begin
    setlength(xy_array,maxstars);
    ditherx:=0;// dither offset
    dithery:=0;
  end;

  min_SNR:=finternalguider.minSNR;//make local to reduce some CPU load
  min_HFD:=finternalguider.minHFD;//make local to reduce some CPU load

  // Divide the image in square areas. Try to detect a star in each area. Store the star position and flux in the xy_array
  if initialize then
  begin
    mean_hfd:=0;
    fitsy:=stepsize div 2;
    repeat
      fitsx:=stepsize div 2;
      repeat
        guidefits.GetHFD3(fitsX+6,fitsY,searchA,true{autocenter},xc,yc,bg,bgdev,hfd1,star_fwhm,vmax,snr,flux,false);//find a star in this segment. Auto center is true

        if ((snr>Min_SNR) and (hfd1>Min_HFD) and (abs(fitsX-xc)<stepsize div 2) and (abs(fitsY-yc)<stepsize div 2) and (star_counter<maxstars))  then //detection and no other area closer
        begin // star in this area
          xy_array[star_counter].x1:=xc;//store initial measured position for recovering if star is lost
          xy_array[star_counter].y1:=yc;

          xy_array[star_counter].x2:=xc;//store measured star position
          xy_array[star_counter].y2:=yc;
          xy_array[star_counter].flux:=flux;
          mean_hfd:=mean_hfd+hfd1;

          inc(star_counter);

          // max value for guide log
          LogSNR:=max(LogSNR,snr);
          LogFlux:=max(LogFlux,flux);

          // Annotate the star
          r:=round(hfd1*3);
          rxc:=round(xc);
          ryc:=round(yc);
          FGuideBmp.Canvas.Frame(rxc-r,ryc-r,rxc+r,ryc+r);
        end;

        inc(fitsx,stepsize);
      until fitsx>=xsize-1+stepsize div 2;;
      inc(fitsy,stepsize);
    until fitsy>=ysize-1+stepsize div 2;

    setlength(xy_array,star_counter);
    setlength(xy_array_old,star_counter);//for later
    if star_counter>0 then
    begin
      mean_hfd:=mean_hfd/star_counter;
      WriteLog('INFO: SET LOCK POSITION, Star(s)='+inttostr(star_counter)+', HFD='+floattostrF(mean_hfd,FFgeneral,3,3));
      msg(inttostr(star_counter)+' guide stars used',3);
    end;
  end
  else
  begin //second, third ... call
    for i:=0 to length(xy_array_old)-1 do
    begin
      if xy_array_old[i].flux<>0 then // Previouse dection, keep tracking this star while it drifts away
      begin //try first within a small area
        guidefits.GetHFD3(round(xy_array_old[i].x2),round(xy_array_old[i].y2),round(mean_hfd*3.5){smaller search area},true{autocenter},xc,yc,bg,bgdev,hfd1,star_fwhm,vmax,snr,flux,false);
       if snr<1 then // no detection, look wider
        guidefits.GetHFD3(round(xy_array_old[i].x2),round(xy_array_old[i].y2),searchA{area},true{autocenter},xc,yc,bg,bgdev,hfd1,star_fwhm,vmax,snr,flux,false) // use a larger search area
      end
      else // try in the initial area
        guidefits.GetHFD3(round(xy_array_old[i].x1),round(xy_array_old[i].y1),searchA,true{autocenter},xc,yc,bg,bgdev,hfd1,star_fwhm,vmax,snr,flux,false);// find a star in the orginal segment

      if ((snr>max(min_SNR-10,6)) and (hfd1>Min_HFD)) then // star detection
      begin // star in this area
        xy_array[i].x2:=xc;
        xy_array[i].y2:=yc;
        xy_array[i].flux:=flux;
        inc(star_counter);

        // max value for guide log
        LogSNR:=max(LogSNR,snr);
        LogFlux:=max(LogFlux,flux);

        // Mark star area
        r:=round(hfd1*3);
        rxc:=round(xc);
        ryc:=round(yc);
        FGuideBmp.Canvas.Frame(rxc-r,ryc-r,rxc+r,ryc+r);

      end
      else
      begin //Star lost temporary
        xy_array[i].flux:=0;
      end;
    end;
  end;
  if star_counter<1 then
  begin
    msg('No stars detected!',1);
    initialize:=true;// Return initialize=true for fresh restart next call.
    exit;
  end;

  // calculate movement in each area
  counter:=0;
  if ((initialize=false) and (length(xy_array_old)>0)) then//not empthy, second round or later
  begin
    len:=length(xy_array_old);
    setlength(drift_arrayX,len);
    setlength(drift_arrayY,len);
    for i:=0 to len-1 do
    begin
      fluxratio:=xy_array_old[i].flux/(xy_array[i].flux+0.001);
      if  ((fluxratio>0.5) and (fluxratio<2)) then //star flux is similar
      begin
        drift_arrayX[counter]:=xy_array[i].x2 - xy_array_old[i].x1+ditherX; //drift in pixels relative to initial measurement x1,y1
        drift_arrayY[counter]:=xy_array[i].y2 - xy_array_old[i].y1+ditherY;
        inc(counter);
      end;
    end;
    if counter/star_counter<0.5 then  // second round and less the 50% of stars are detected
      msg('Guider, warning lost track or exposure time changed!',2); //more then 7.5 pixels drift in one cycle

    // Remove outliers and calculate mean drift in X and Y.
    get_best_mean(drift_arrayX,counter {length},drX );
    get_best_mean(drift_arrayY,counter {length},drY );
  end;

  for i:=0 to length(xy_array_old)-1 do // copy xy_array to xy_array_old
      xy_array_old[i]:=xy_array[i];
  initialize:=false;// success, first data collected
  result:=0; // good result
end;


procedure T_autoguider_internal.InternalguiderLoop;
begin
  SetStatus('Looping Exposures',GUIDER_IDLE);
  StopInternalguider:=false;
  InternalguiderRunning:=true;
  Finternalguider.ButtonLoop.enabled:=false;
  Finternalguider.ButtonCalibrate.enabled:=false;
  Finternalguider.ButtonGuide.enabled:=false;
  Finternalguider.ButtonDark.enabled:=false;
  if InternalguiderCapturingDark then begin
    FGuideFits.SetBPM(bpm,0,0,0,0);
    FGuideFits.DarkOn:=false;
    FCamera.AddFrames:=true;
    FCamera.StackNum:=12;
    FCamera.SaveFrames:=false;
    FCamera.AlignFrames:=false;
    FCamera.StackOperation:=1;
    FCamera.StackAllow8bit:=true;
    FCamera.StackUseDark:=false;
    FCamera.StackDebayer:=false;
  end
  else begin
    FGuideFits.SetBPM(bpm,0,0,0,0);
    FGuideFits.DarkOn:=true;
    FCamera.AddFrames:=false;
    FCamera.StackNum:=-1;
    FCamera.StackAllow8bit:=false;
    FCamera.SaveFrames:=false;
    FCamera.AlignFrames:=false;
  end;
  StartGuideExposure;
end;

Procedure T_autoguider_internal.StartGuideExposureAsync(Data: PtrInt);
begin
  StartGuideExposure;
end;

Procedure T_autoguider_internal.StartGuideExposure;
var e: double;
    binx,biny,gain: integer;
begin
if (FCamera.Status=devConnected) then begin
  // check exposure time
  e:=finternalguider.Exposure.value;
  binx:=finternalguider.Binning.Value;
  biny:=binx;
  if (binx<FCamera.BinXrange.min)or(biny<FCamera.BinYrange.min) or
     (binx>FCamera.BinXrange.max)or(biny>FCamera.BinYrange.max)
     then begin
        msg(Format(rsInvalidBinni, [inttostr(binx)]),1);
        InternalguiderStop;
        exit;
     end;
     if (FCamera.BinX<>binx)or(FCamera.BinY<>biny) then begin
        FCamera.SetBinning(binx,biny);
     end;
  if FCamera.hasGain then begin
    gain:=finternalguider.Gain.Value;
    if FCamera.Gain<>gain then begin
      FCamera.Gain:=gain;
    end;
    if FCamera.hasOffset then begin
       if FCamera.Offset<>finternalguider.Offset.Value then
         FCamera.Offset:=finternalguider.Offset.Value;
    end;
  end;
  if InternalguiderCapturingDark then begin
    if (FCamera.FrameType<>DARK) then
      FCamera.FrameType:=DARK
  end
  else if FCamera.FrameType<>LIGHT then
    FCamera.FrameType:=LIGHT;
  FCamera.ObjectName:=rsGuide;

  FCamera.StartExposure(e);

end
else begin
   InternalguiderStop;
   if not AllDevicesConnected then msg(rsSomeDefinedD,1);
end;
end;

procedure T_autoguider_internal.InternalguiderStart;
begin
  SetStatus('Start Guiding',GUIDER_BUSY);
  Application.QueueAsyncCall(@InternalguiderStartAsync,0);
end;

procedure T_autoguider_internal.InternalguiderStartAsync(Data: PtrInt); {internal guider}
var
  i: integer;
  txt: string;
begin
  if AllDevicesConnected=false then
  begin
    msg('Internal guider: Devices not connected!',1);
    SetStatus('Devices not connected',GUIDER_ALERT);
    exit;
  end;
  if FCamera.Status<>devConnected then
  begin
    msg('Internal guider: Guide camera not connected!',1);
    SetStatus('Guide camera not connected',GUIDER_ALERT);
    exit;
  end;
  if Fmount.canpulseguide=false then
  begin
    msg('Abort, mount does not support pulse guiding!',1);
    SetStatus('Mount not supported',GUIDER_ALERT);
    exit;
  end;


  if InternalguiderGuiding then
  begin
    // already starting
    exit;
  end;
  SetStatus('Start Guiding',GUIDER_BUSY);
  StopInternalguider:=false;
  InternalguiderGuiding:=true;
  FPaused:=false;

  if Fmount.Tracking=false then
  begin
    msg('Start tracking. Wait 20 seconds',2);
    Fmount.Track;//start tracking
    wait(20);
  end;

  Fmount.GuideRateRa:=0.5*360/(24*60*60);//set pulse gain at 0.5x & 1.5 tracking. Same as calibration

  setlength(xy_trend,nrpointsTrend,4);
  for i:=0 to nrpointsTrend-1 do {clear}
  begin
   xy_trend[i,0]:=1E100;//delta ra, 1E100 is an empthy marker
   xy_trend[i,1]:=0;//delta dec
   xy_trend[i,2]:=0;//ra correction
   xy_trend[i,3]:=0 //dec correction
  end;

  old_moveRA:=0;
  old_moveDEC:=0;

  InternalguiderInitialize:=true; //initialize;

  // initialize the guide log
  GuideFrameCount:=0;
  GuideStartTime:=now;
  WriteLog('Guiding Begins at '+FormatDateTime('YYYY-MM-DD HH:NN:SS',GuideStartTime));
  WriteLog('Equipment Profile = '+profile);
  txt:='Dither = ';
  if DitherRAonly then
    txt:=txt+'RA only'
  else
    txt:=txt+'both axes';
  txt:=txt+', Dither scale = '+formatfloat(f3,DitherPixel);
  WriteLog(txt);
  WriteLog('Pixel scale = '+FormatFloat(f2,Finternalguider.pixel_size)+' arc-sec/px');
  WriteLog('RA Gain = '+IntToStr(Finternalguider.RAgain)+', RA Hyst = '+IntToStr(Finternalguider.RA_hysteresis));
  WriteLog('DEC Gain = '+IntToStr(Finternalguider.DECgain)+', DEC Hyst = '+IntToStr(Finternalguider.DEC_hysteresis));
  WriteLog('Pulse gain East = '+FormatFloat(f2,Finternalguider.pulsegainEast)+', Pulse gain West = '+FormatFloat(f2,Finternalguider.pulsegainWest));
  WriteLog('Pulse gain North = '+FormatFloat(f2,Finternalguider.pulsegainNorth)+', Pulse gain South = '+FormatFloat(f2,Finternalguider.pulsegainSouth));
  WriteLog('Shortest guide pulse setting = '+IntToStr(Finternalguider.shortestPulse));
  WriteLog('Minimum HFD setting = '+FormatFloat(f2,Finternalguider.minHFD));
  WriteLog('Minimum SNR setting = '+FormatFloat(f2,Finternalguider.minSNR));

  WriteLog('');
  WriteLog('Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode');

  InternalguiderLoop;
  StartSettle;

end;

procedure T_autoguider_internal.InternalAutoguiding;
var i,maxpulse: integer;
    RADuration,DECDuration: LongInt;
    RADirection,DECDirection: string;
    mflipcorr,moveRA2,dsettle : double;

begin
 if not FPaused then begin

  // Plot graph
  if not FSettling then begin
    finternalguider.draw_xy(xy_trend);//plot xy values
    finternalguider.draw_trend(xy_trend);// plot trends
    for i:=nrpointsTrend-2 downto 0 do {shift values and make place for new values}
    begin
     xy_trend[i+1,0]:=xy_trend[i,0];//x value
     xy_trend[i+1,1]:=xy_trend[i,1];//y value
     xy_trend[i+1,2]:=xy_trend[i,2];//x correction
     xy_trend[i+1,3]:=xy_trend[i,3];//y correction
    end;
  end;

  //Measure drift
  if measure_drift(InternalguiderInitialize,driftX,driftY)=2 then exit;// ReferenceX,Y indicates the total drift, driftX,driftY to drift since previous call. Arrays xy_array_old,xy_array are for storage star positions
  if InternalguiderInitialize then begin
     SetStatus(StarLostStatus,GUIDER_ALERT);
     exit; //until star(s) detected. If no stars are detected initialize is returned true
  end;

  // Process settling
  if FSettling then begin
     if ((now-FSettleStartTime)*SecsPerDay)<FSettleTmax then begin
       // check current distance
       dsettle:=sqrt(driftx*driftx+drifty*drifty);
       if dsettle<=FSettlePix then begin
         // distance in range
         if FSettlingInRange then begin
           // check for how long we are in range
           if ((now-FSettleTime)*SecsPerDay)>=FSettleTmin then begin
             // settling complete
             FSettling:=false;
             SetStatus('Guiding',GUIDER_GUIDING);
             WriteLog('INFO: SETTLING STATE CHANGE, Settling complete');
           end;
         end
         else begin
           // initialize in range
           FSettlingInRange:=true;
           FSettleTime:=now;
         end;
       end
       else begin
         // no more in range
         FSettlingInRange:=false;
       end;
     end
     else begin
       // timeout reach
       FSettling:=false;
       SetStatus('Guiding',GUIDER_GUIDING);
       WriteLog('INFO: SETTLING STATE CHANGE, Settling failed');
     end;
  end;

  // Apply camera orientation and meridian flip if required
  if (mount.PierSide=pierWest) <> (pos('E',finternalguider.pier_side)>0) then // Did a meridian flip occur since calibration.
    mflipcorr:=180 // A meridian flip occurred
  else
    mflipcorr:=0;
  rotate2((- (finternalguider.PA+mflipcorr)*pi/180),driftX,driftY, driftRA,driftDec);{rotate a vector point, counter clockwise}

  if finternalguider.pulsegainNorth<0 then driftDEC:=-driftDEC;//flipped image correction. E.g. an image where north is up and east on the right size.

  xy_trend[0,0]:=-DriftRa;//store RA drift in pixels.
  xy_trend[0,1]:=+DriftDec;//store DEC drift in pixels.



  if finternalguider.disable_guiding=false then //guiding enabled
  begin
    //calculate required RA correction in pixels
    moveRA:=(- driftRA*(1 - finternalguider.RA_hysteresis/100) +   old_moveRA * finternalguider.RA_hysteresis/100 ) * finternalguider.RAgain/100;//Hysteresis as in PHD1
    old_moveRA:=moveRA;//Store for next cycle hysteresis calculation

    //calculate required DEC correction in pixels
    moveDEC:=(- driftDEC*(1 - finternalguider.DEC_hysteresis/100) +   old_moveDEC * finternalguider.DEC_hysteresis/100 ) * finternalguider.DECgain/100;//Hysteresis as in PHD1
    old_moveDEC:=moveDEC;//Store for next cycle hysteresis calculation


    Guidethecos:=cos(mount.Dec*pi/180); if Guidethecos=0 then Guidethecos:=0.000001;
    moveRA2:=moveRA/Guidethecos; //correct pixels with cos(dec). Rotation in pixels near celestial pole decreases with cos(dec)

    pulseRA:=0;
    pulseDEC:=0;
    RADuration:=0;
    RADirection:='';
    DECDuration:=0;
    DECDirection:='';

    if moveRA2>0 then //going East increases the RA
    begin
       pulseRA:=min(max_duration,round(1000*abs(moveRA2/finternalguider.pulsegainEast))); {duration msec}
       if pulseRA>finternalguider.shortestPulse then //Large enough correction to follow by motors/relays. Complementary with minimum_move
       begin
         //msg('East: '+inttostr(pulseRA),3);
         mount.PulseGuide(2,pulseRA);  // 0=north, 1=south, 2 East, 3 West
         RADuration:=abs(pulseRA);
         RADirection:='E';
       end
       else moveRA:=0; // for trend in pixels
    end
    else
    if moveRA2<0 then //going West
    begin
      pulseRA:=min(max_duration,round(1000*abs(moveRA2/finternalguider.pulsegainWest))); {duration msec}
      if pulseRA>finternalguider.shortestPulse then
      begin
        //msg('West: '+inttostr(pulseRA),3);
        mount.PulseGuide(3,pulseRA);  // 0=north, 1=south, 2 East, 3 West
        RADuration:=abs(pulseRA);
        RADirection:='W';
      end
       else moveRA:=0; // for trend in pixels
    end;

    if moveDEC>0 then //go North increase the DEC.
    begin
      pulseDEC:=min(max_duration,round(1000*abs(moveDEC/finternalguider.pulsegainNorth))); {duration msec}
      if pulseDEC>finternalguider.shortestPulse then
      begin
        //msg('North: '+inttostr(pulseDEC),3);
        mount.PulseGuide(0,pulseDEC);  // 0=north, 1=south, 2 East, 3 West
        DECDuration:=abs(pulseDEC);
        DECDirection:='N';
      end
      else moveDEC:=0; // for trend in pixels
    end
    else
    if moveDEC<0 then //go South
    begin
      pulseDEC:=min(max_duration,round(1000*abs(moveDEC/finternalguider.pulsegainSouth))); {duration msec}
      if pulseDEC>finternalguider.shortestPulse then
      begin
        //msg('South: '+inttostr(pulseDEC),3);
        mount.PulseGuide(1,pulseDEC);  // 0=north, 1=south, 2 East, 3 West
        DECDuration:=abs(pulseDEC);
        DECDirection:='S';
      end
      else moveDEC:=0; // for trend in pixels
    end;


    // wait for puls guide move completed
    maxpulse:=max(pulseRA,pulseDEC);
    if maxpulse>finternalguider.shortestPulse then
    begin
      WaitPulseGuiding(maxpulse);
    end;

    xy_trend[0,2]:=-moveRA;//store RA correction in pixels for trend
    xy_trend[0,3]:=+moveDEC;//store DEC correction in pixels for trend


    if InternalguiderRunning then begin
      // write log
      inc(GuideFrameCount);
      //Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode
      WriteLog(IntToStr(GuideFrameCount)+','+
               FormatFloat(f3,(now-GuideStartTime)*secperday)+','+
               '"Mount"'+','+
               FormatFloat(f3,driftX)+','+
               FormatFloat(f3,driftY)+','+
               FormatFloat(f3,driftRA)+','+
               FormatFloat(f3,driftDec)+','+
               FormatFloat(f3,moveRA)+','+
               FormatFloat(f3,moveDEC)+','+
               IntToStr(RADuration)+','+
               RADirection+','+
               IntToStr(DECDuration)+','+
               DECDirection+','+
               ',,'+  // AO
               FormatFloat(f0,LogFlux)+','+
               FormatFloat(f2,LogSNR)+','+
               '0'    // error code
               );
    end;

  end //guiding enabled
  else
  begin  //guiding disabled
    xy_trend[0,2]:=0;
    xy_trend[0,3]:=0;
  end;
 end;
end;

function T_autoguider_internal.WaitPulseGuiding(pulse:longint): boolean;
var
   thesleep : integer;
begin
  result:=false;
  repeat
    thesleep:=(min(100,pulse));
    sleep(thesleep);
    dec(pulse,thesleep);
    CheckSynchronize();
    if StopInternalguider then
    begin
      msg('Guider stop pressed.',3);
      exit;
    end;
  until pulse<=0;
  result:=true;
end;

procedure T_autoguider_internal.InternalguiderStop;
begin
  if (not InternalguiderCapturingDark)and(not StopInternalguider) then begin
    WriteLog('Guiding Ends at '+FormatDateTime('YYYY-MM-DD HH:NN:SS',now));
    WriteLog('');
  end;
  StopInternalguider:=true;
  InternalguiderRunning:=false;
  InternalguiderGuiding:=false;
  InternalguiderCalibrating:=false;
  InternalguiderCapturingDark:=false;
  Finternalguider.ButtonLoop.enabled:=true;
  Finternalguider.ButtonCalibrate.enabled:=true;
  Finternalguider.ButtonGuide.enabled:=true;
  Finternalguider.ButtonDark.enabled:=true;
  Finternalguider.led.Brush.Color:=clGray;
  SetStatus('Stopped',GUIDER_IDLE);
end;


procedure T_autoguider_internal.InternalguiderCalibrate;
begin
  if AllDevicesConnected=false then
  begin
    msg('Internal guider: Devices not connected!',1);
    InternalguiderStop;
    exit;
  end;
  if FCamera.Status<>devConnected then
  begin
    msg('Internal guider: Guide camera not connected!',1);
    SetStatus('Guide camera not connected',GUIDER_ALERT);
    exit;
  end;
  if Fmount.canpulseguide=false then
  begin
    msg('Abort, mount does not support pulse guiding!',1);
    InternalguiderStop;
    exit;
  end;
  if abs(mount.Dec)>60 then
  begin
    msg('Abort, calibration at high declination is not possible!',1);
    InternalguiderStop;
    exit;
  end;

  StopInternalguider:=false;
  InternalguiderCalibrating:=true;
  SetStatus('Start Calibration',GUIDER_BUSY);

  finternalguider.trend_message('Guider is in calibration mode.','This will take a few minutes.','');

  if mount.Tracking=false then
  begin
    msg('Start tracking. Wait 20 seconds',3);
    mount.Track;//start tracking
    wait(20);
  end;

  Calthecos:=cos(mount.Dec*pi/180); if Calthecos=0 then Calthecos:=0.00000001; //prevent dividing by zero

  InternalguiderCalibrationDirection:=1;
  InternalguiderCalibrationStep:=0;

  InternalguiderLoop;
end;

procedure T_autoguider_internal.InternalCalibration;
var drift,thetime,loopLatency,unequal   : double;
    i                                   : integer;
    msgA, msgB                          : string;
            procedure StopError;
            begin
              InternalguiderStop;
              msg('Calibration error',1);
              SetStatus('Calibration Failed',GUIDER_ALERT);
              raise exception.Create('Calibration error');
            end;
begin
  try
    case InternalguiderCalibrationDirection of
    1:begin  //EAST, measure pulse guide speed
        case InternalguiderCalibrationStep of
          0: begin
               //force speed
               Fmount.GuideRateRa:=0.5*360/(24*60*60);//set pulse gain at 0.5x & 1.5 tracking

               thetime:=now;
               mount.PulseGuide(2,CalibrationDuration {duration msec} );  // 0=north, 1=south, 2 East, 3 West
               repeat
                 sleep(10);
                 if mount.PulseGuiding then break;
                 inc(i);
               until i>200;//max 2 seconds
               loopLatency:=(now-thetime)*secperday*1000;
               msg('Mount loop latency '+floattostrF(loopLatency/1000,FFgeneral,0,3)+ ' ms',2);

               CalibrationDuration:=667; //duration of pulse guiding
               InternalguiderCalibrationStep:=1;
               InternalCalibration; // iterate without new image
             end;
          1: begin
               CalibrationDuration:=round(CalibrationDuration*1.5);
               msg('Testing pulse guiding East for '+floattostrF(CalibrationDuration/1000,FFgeneral,0,2)+ ' seconds',2);
               InternalCalibrationInitialize:=true;
               if measure_drift(InternalCalibrationInitialize,driftX,driftY)>0 then StopError;//measure reference star positions
               mount.PulseGuide(2,CalibrationDuration {duration msec} );  // 0=north, 1=south, 2 East, 3 West

               //msg('waiting '+ inttostr(CalibrationDuration),3);

               WaitPulseGuiding(CalibrationDuration);
               InternalguiderCalibrationStep:=2;
             end;
          2: begin
               if measure_drift(InternalCalibrationInitialize,driftX,driftY)>0 then StopError;//measure drift
               drift:=sqrt(sqr(driftX)+sqr(driftY));//  For image with north up and east left, driftX become negative.


               msg('Measured drift ' + floattostrf(drift,ffgeneral,0,2)+' px',3);
               if ((drift>5) or (CalibrationDuration>20000)) then begin// OK, next direction
                 if drift<2 then begin msg('Abort calibration, no movement measured!',1); StopError; end;
                 pulsegainEast:=drift*1000/(CalibrationDuration*Calthecos); // [px*cos(dec)/sec]
                 paEast:=arctan2(driftY,driftX);//-pi..pi, For north up and east left this gives zero angle
                 InternalguiderCalibrationDirection:=2;
                 InternalguiderCalibrationStep:=0;
               end
               else begin // retry with bigger pulse
                 InternalguiderCalibrationStep:=1;
               end;
             end;
        end;
      end;
    2:begin  //WEST, measure pulse guide. Use same duration as East
        case InternalguiderCalibrationStep of
          0: begin
               msg('Testing pulse guiding West for '+floattostrF(CalibrationDuration/1000,FFgeneral,0,2)+ ' seconds',2);
               InternalCalibrationInitialize:=true;
               if measure_drift(InternalCalibrationInitialize,driftX,driftY)>0 then StopError;//measure reference star positions
               mount.PulseGuide(3,CalibrationDuration {duration msec} );  // 0=north, 1=south, 2 East, 3 West

               //msg('waiting '+ inttostr(CalibrationDuration),3);

               WaitPulseGuiding(CalibrationDuration);
               InternalguiderCalibrationStep:=1;
             end;
          1: begin
               if measure_drift(InternalCalibrationInitialize,driftX,driftY)>0 then StopError;//measure drift
               drift:=sqrt(sqr(driftX)+sqr(driftY)); //For image with north up and east left, driftX become positive.

               msg('Measured drift ' + floattostrf(drift,ffgeneral,0,2)+' px',3);
               pulsegainWest:=drift*1000/(CalibrationDuration*Calthecos); // [px*cos(dec)/sec]
               msg('Internal guider calibration:  Pulse gain measured East/West: '+ floattostrF(pulsegainEast,ffgeneral,0,2)+'/'+ floattostrF(pulsegainWest,ffgeneral,0,2)+' [px*cos(δ)/sec], Camera angle: '+floattostrF(paEast*180/pi,ffgeneral,3,1)+'°',3);
               InternalguiderCalibrationDirection:=3;
               InternalguiderCalibrationStep:=0;
               InternalCalibration;  // iterate without new image
             end;
        end;
      end;
    3:begin  //NORTH measure pulse guide speed.
        case InternalguiderCalibrationStep of
          0: begin
               msg('Slew North to remove backlash',3);
               mount.Slew(mount.ra,mount.dec+1.0);//move one degree north
               WaitPulseGuiding(1000);//wait till vibrations are gone. Required?
               CaldriftOld:=0;
               CalibrationDuration:=667; //duration of pulse guiding
               InternalguiderCalibrationStep:=1;
             end;
          1: begin
               CalibrationDuration:=round(CalibrationDuration*1.5);
               msg('Testing pulse guiding North for '+floattostrF(CalibrationDuration/1000,FFgeneral,0,2)+ ' seconds',3);
               InternalCalibrationInitialize:=true;//for measure drift
               if measure_drift(InternalCalibrationInitialize,driftX,driftY)>0 then StopError;//measure reference star positions
               mount.PulseGuide(0,CalibrationDuration {duration msec} );  // 0=north, 1=south, 2 East, 3 West
               WaitPulseGuiding(CalibrationDuration);
               InternalguiderCalibrationStep:=2;
             end;
          2: begin
               if measure_drift(InternalCalibrationInitialize,driftX,driftY)>0 then StopError;//measure drift
               drift:=sqrt(sqr(driftX)+sqr(driftY));

               msg('Measured drift ' + floattostrf(drift,ffgeneral,0,2)+' px',3);
               if ( ((drift>5) and (CaldriftOld>5/1.5)) or (CalibrationDuration>20000)) then begin// OK both drift and CaldriftOld show movement so backlash must be fully gone. Go next direction
                 if drift<2 then begin msg('Abort calibration, no movement measured!',1); StopError; end;
                 paNorth:=arctan2(driftY,driftX); // Relative to the positive X axis and CCW
                 Caltheangle:=paNorth - paEast;// CCW angles, calculate angle North relative to West
                 if Caltheangle<pi then Caltheangle:=Caltheangle+pi*2;
                 if Caltheangle>pi then Caltheangle:=Caltheangle-pi*2;
                 if  Caltheangle>0 then //is turning to from West to North positive or negative pi/2
                   Calflip:=+1  // Normal. If North is up then East is left in the image
                 else
                   Calflip:=-1; // Flipped image. E.g.if North is up then East is on the right side}
                 pulsegainNorth:=Calflip*drift*1000/(CalibrationDuration); // [px/sec]

                 InternalguiderCalibrationDirection:=4;
                 InternalguiderCalibrationStep:=0;
                 InternalCalibration;  // iterate without new image
               end
               else begin // retry with bigger pulse
                 CaldriftOld:=drift;
                 InternalguiderCalibrationStep:=1;
               end;
             end;
        end;
      end;
    4:begin  //SOUTH, measure pulse guide speed.
        case InternalguiderCalibrationStep of
          0: begin
               msg('Slew South to remove backlash',3);
               mount.Slew(mount.ra,mount.dec-1);// move one degree south
               WaitPulseGuiding(1000);//wait till vibrations are gone. Required?
               CalCount:=0;
               CaldriftOld:=0;
               InternalguiderCalibrationStep:=1;
               msg('Testing pulse guiding South for '+floattostrF(CalibrationDuration/1000,FFgeneral,0,2)+ ' seconds',3);
             end;
          1: begin
               InternalCalibrationInitialize:=true;
               if measure_drift(InternalCalibrationInitialize,driftX,driftY)>0 then StopError;//measure reference star positions
               mount.PulseGuide(1,CalibrationDuration {duration msec} );  // 0=north, 1=south, 2 East, 3 West
               WaitPulseGuiding(CalibrationDuration);
               InternalguiderCalibrationStep:=2;
             end;
          2: begin
               if measure_drift(InternalCalibrationInitialize,driftX,driftY)>0 then StopError;//measure drift
               drift:=sqrt(sqr(driftX)+sqr(driftY));
               inc(CalCount);
               msg('Measured drift ' + floattostrf(drift,ffgeneral,0,2)+' px',3);
               if ((CaldriftOld>3) or (Calcount>=4)) then begin  //previous cycle showed movement so backlash must be fully gone
                 if drift<2 then begin msg('Abort calibration, no movement measured!',1); StopError; end;
                 pulsegainSouth:=Calflip*drift*1000/(CalibrationDuration); // [px*cos(dec)/sec]   Flipped is already measured
                 msg('Internal guider calibration:  Pulse gain measured North/South: '+ floattostrF(pulsegainNorth,ffgeneral,0,2)+'/'+ floattostrF(pulsegainSouth,ffgeneral,0,2)+' [px/sec]',3);


                 //measure first minimum pulse north. Backlash is gone after testing speed north
                 InternalguiderCalibrationDirection:=5;
                 InternalguiderCalibrationStep:=0;
                 InternalCalibration;  // iterate without new image
               end
               else begin
                 CaldriftOld:=drift;
                 InternalguiderCalibrationStep:=1; //repeat loop until CaldriftOld>2 and backlash is gone
               end;
             end;
        end;
      end;
    5:begin  //Display findings
        if mount.PierSide=pierWest then finternalguider.pier_side:='E' else finternalguider.pier_side:='W'; //measured west or east ??
        finternalguider.PA:=paEast*180/pi; // this is the relative angle between the image and the mount.
        finternalguider.pulsegainEast:=pulsegainEast;
        finternalguider.pulsegainWest:=pulsegainWest;
        finternalguider.pulsegainNorth:=pulsegainNorth;
        finternalguider.pulsegainSouth:=pulsegainSouth;

        finternalguider.pixel_size:=0.5*15*2/(pulsegainEast+pulsegainWest);//Assume 0.5x and 1.5x pulse speed as set previously

        if finternalguider.measure_method2.checked then begin  //Alternative method. Measure pixel size in arc seconds by stopping tracking
          InternalguiderCalibrationDirection:=6;
          InternalguiderCalibrationStep:=0;
          InternalCalibration;  // iterate without new image
        end
        else begin
          InternalguiderCalibrationDirection:=7;
          InternalguiderCalibrationStep:=0;
          InternalCalibration;  // iterate without new image
        end;
      end;
    6:begin //Optional, measure pixel scale guider camera in arcseconds. Do not initialize, use the position from the South measurement
        case InternalguiderCalibrationStep of
          0: begin
               msg('Stop tracking a few times for 0.5 seconds to measure pixel scale',1);
               InternalCalibrationInitialize:=true;
               if measure_drift(InternalCalibrationInitialize,driftX,driftY)>0 then StopError;//measure reference star positions
               mount.AbortMotion;// stop to measure the pixel scale. Assume scale is 1"/px or larger. This results in 7.5 pixel drift max.
               sleep(500);
               mount.Track;//start tracking again
               Calnrtest:=1;
               InternalguiderCalibrationStep:=1;
             end;
          1: begin
               if measure_drift(InternalCalibrationInitialize,driftX,driftY)>0 then //sync the drift measurement with the new position.
               begin
                 msg('Used alternative method to calculate the pixel scale.',1);
                 InternalguiderCalibrationDirection:=7;
                 InternalguiderCalibrationStep:=0;
                 InternalCalibration;  // iterate without new image
               end;
               if Calnrtest<8 then begin
                 mount.AbortMotion;// stop to measure the pixel scale. Assume scale is 1"/px or larger. This results in 7.5 pixel drift max.
                 sleep(500);
                 mount.Track;//start tracking again
                 inc(Calnrtest);
                 InternalguiderCalibrationStep:=1;
               end
               else begin
                 InternalguiderCalibrationStep:=2;
               end;
             end;
          2: begin
               drift:=sqrt(sqr(driftX)+sqr(driftY));
               finternalguider.pixel_size:=Calnrtest*0.5*15/drift;
               msg('Total drift: '+ floattostrF(drift,ffgeneral,0,2)+ ' pixels after '+inttostr(Calnrtest)+ ' tracking stops of 0.5 seconds. Estimated pixel size '+floattostrF(finternalguider.pixel_size,ffgeneral,0,2)+' "/px' ,3);
               InternalguiderCalibrationDirection:=7;
               InternalguiderCalibrationStep:=0;
               InternalCalibration;  // iterate without new image
             end;
        end;
      end;
    7:begin

        unequal:=abs(1-(pulsegainEast/pulsegainWest));
        if unequal>0.2 then begin msgA:='Warning unequal East/West pulse gain!'; msg(msgA,1); end else msgA:='';
        unequal:=abs(1-(pulsegainNorth/pulsegainSouth));
        if unequal>0.2 then begin msgB:='Warning unequal North/South pulse gain!'; msg(msgB,1); end else msgB:='';

        msg('Ready to guide!',1);
        finternalguider.trend_message('Calibration is ready.',msgA,msgB);
        InternalguiderStop;
        SetStatus('Calibration Complete',GUIDER_IDLE);
      end;
  end;
  except
  end;
end;

procedure T_autoguider_internal.InternalguiderCaptureDark;
begin
  if FCamera.Status<>devConnected then
  begin
    msg('Internal guider: Guide camera not connected!',1);
    exit;
  end;

  StopInternalguider:=false;
  InternalguiderCapturingDark:=true;
  SetStatus('Capture dark',GUIDER_BUSY);
  InternalguiderLoop;
end;

end.


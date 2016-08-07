unit cu_indimount;

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

uses cu_mount, indibaseclient, indibasedevice, indiapi, indicom,
     u_global, ExtCtrls, Forms, Classes, SysUtils;

type

T_indimount = class(T_mount)
 private
   indiclient: TIndiBaseClient;
   InitTimer: TTimer;
   ConnectTimer: TTimer;
   MountDevice: Basedevice;
   Mountport: ITextVectorProperty;
   coord_prop: INumberVectorProperty;
   coord_ra:   INumber;
   coord_dec:  INumber;
   CoordSet: ISwitchVectorProperty;
   CoordSetTrack,CoordSetSlew,CoordSetSync: ISwitch;
   parkprop: ISwitchVectorProperty;
   swpark,swunpark: ISwitch;
   AbortmotionProp: ISwitchVectorProperty;
   TelescopeInfo: INumberVectorProperty;
   TelescopeAperture, TelescopeFocale: INumber;
   eod_coord:  boolean;
   configprop: ISwitchVectorProperty;
   configload,configsave,configdefault: ISwitch;
   Fready,Fconnected: boolean;
   Findiserver, Findiserverport, Findidevice, Findideviceport: string;
   procedure CreateIndiClient;
   procedure InitTimerTimer(Sender: TObject);
   procedure ConnectTimerTimer(Sender: TObject);
   procedure ClearStatus;
   procedure CheckStatus;
   procedure NewDevice(dp: Basedevice);
   procedure NewMessage(txt: string);
   procedure NewProperty(indiProp: IndiProperty);
   procedure NewNumber(nvp: INumberVectorProperty);
   procedure NewText(tvp: ITextVectorProperty);
   procedure NewSwitch(svp: ISwitchVectorProperty);
   procedure NewLight(lvp: ILightVectorProperty);
   procedure DeleteDevice(dp: Basedevice);
   procedure DeleteProperty(indiProp: IndiProperty);
   procedure ServerConnected(Sender: TObject);
   procedure ServerDisconnected(Sender: TObject);
   procedure LoadConfig;
   procedure msg(txt: string);
 protected
   procedure SetPark(value:Boolean); override;
   function  GetPark:Boolean; override;
   function  GetRA:double; override;
   function  GetDec:double; override;
   function  GetEquinox: double;  override;
   function  GetAperture:double;  override;
   function  GetFocaleLength:double; override;
   procedure SetTimeout(num:integer); override;
 public
   constructor Create(AOwner: TComponent);override;
   destructor  Destroy; override;
   Procedure Connect(cp1: string; cp2:string=''; cp3:string=''; cp4:string=''); override;
   Procedure Disconnect; override;
   function Slew(sra,sde: double):boolean; override;
   function Sync(sra,sde: double):boolean; override;
   function Track:boolean; override;
   procedure AbortMotion; override;
end;

implementation

procedure T_indimount.CreateIndiClient;
begin
if csDestroying in ComponentState then exit;
  indiclient:=TIndiBaseClient.Create;
  indiclient.Timeout:=FTimeOut;
  indiclient.onNewDevice:=@NewDevice;
  indiclient.onNewMessage:=@NewMessage;
  indiclient.onNewProperty:=@NewProperty;
  indiclient.onNewNumber:=@NewNumber;
  indiclient.onNewText:=@NewText;
  indiclient.onNewSwitch:=@NewSwitch;
  indiclient.onNewLight:=@NewLight;
  indiclient.onDeleteDevice:=@DeleteDevice;
  indiclient.onDeleteProperty:=@DeleteProperty;
  indiclient.onServerConnected:=@ServerConnected;
  indiclient.onServerDisconnected:=@ServerDisconnected;
  ClearStatus;
end;

constructor T_indimount.Create(AOwner: TComponent);
begin
 inherited Create(AOwner);
 FMountInterface:=INDI;
 ClearStatus;
 Findiserver:='localhost';
 Findiserverport:='7624';
 Findidevice:='';
 Findideviceport:='';
 InitTimer:=TTimer.Create(nil);
 InitTimer.Enabled:=false;
 InitTimer.Interval:=10000;
 InitTimer.OnTimer:=@InitTimerTimer;
 ConnectTimer:=TTimer.Create(nil);
 ConnectTimer.Enabled:=false;
 ConnectTimer.Interval:=3000;
 ConnectTimer.OnTimer:=@ConnectTimerTimer;
 CreateIndiClient;
end;

destructor  T_indimount.Destroy;
begin
 InitTimer.Enabled:=false;
 ConnectTimer.Enabled:=false;
 indiclient.Free;
 FreeAndNil(InitTimer);
 FreeAndNil(ConnectTimer);
 inherited Destroy;
end;

procedure T_indimount.ClearStatus;
begin
    MountDevice:=nil;
    Mountport:=nil;
    TelescopeInfo:=nil;
    parkprop:=nil;
    coord_prop:=nil;
    CoordSet:=nil;
    AbortmotionProp:=nil;
    configprop:=nil;
    Fready:=false;
    Fconnected := false;
    FStatus := devDisconnected;
    if Assigned(FonStatusChange) then FonStatusChange(self);
end;

procedure T_indimount.CheckStatus;
begin
    if Fconnected and
       (configprop<>nil) and
       (coord_prop<>nil)
    then begin
       FStatus := devConnected;
       if (not Fready) then begin
         if Assigned(FonStatusChange) then FonStatusChange(self);
         Fready:=true;
         if FAutoloadConfig then begin
           LoadConfig;
         end;
       end;
    end;
end;

procedure T_indimount.msg(txt: string);
begin
  if Assigned(FonMsg) then FonMsg(Findidevice+': '+txt);
end;

Procedure T_indimount.Connect(cp1: string; cp2:string=''; cp3:string=''; cp4:string='');
begin
if (indiclient=nil)or(indiclient.Terminated) then CreateIndiClient;
if not indiclient.Connected then begin
  Findiserver:=cp1;
  Findiserverport:=cp2;
  Findidevice:=cp3;
  Findideviceport:=cp4;
  FStatus := devDisconnected;
  if Assigned(FonStatusChange) then FonStatusChange(self);
  indiclient.SetServer(Findiserver,Findiserverport);
  indiclient.watchDevice(Findidevice);
  indiclient.ConnectServer;
  FStatus := devConnecting;
  if Assigned(FonStatusChange) then FonStatusChange(self);
  InitTimer.Enabled:=true;
end
else msg('Mount already connected');
end;

procedure T_indimount.InitTimerTimer(Sender: TObject);
begin
  InitTimer.Enabled:=false;
  if (MountDevice=nil)or(not Fready) then begin
     msg('No response from server');
     msg('Is "'+Findidevice+'" a running telescope mount driver?');
     Disconnect;
  end;
end;

Procedure T_indimount.Disconnect;
begin
indiclient.Terminate;
ClearStatus;
end;

procedure T_indimount.ServerConnected(Sender: TObject);
begin
   ConnectTimer.Enabled:=True;
end;

procedure T_indimount.ConnectTimerTimer(Sender: TObject);
begin
 ConnectTimer.Enabled:=False;
  if (Mountport<>nil)and(Findideviceport<>'') then begin
     Mountport.tp[0].text:=Findideviceport;
     indiclient.sendNewText(Mountport);
  end;
 indiclient.connectDevice(Findidevice);
end;

procedure T_indimount.ServerDisconnected(Sender: TObject);
begin
  FStatus := devDisconnected;
  if Assigned(FonStatusChange) then FonStatusChange(self);
  msg('Mount server disconnected');
  CreateIndiClient;
end;

procedure T_indimount.NewDevice(dp: Basedevice);
begin
  //writeln('Newdev: '+dp.getDeviceName);
  if dp.getDeviceName=Findidevice then begin
     Fconnected:=true;
     MountDevice:=dp;
  end;
end;

procedure T_indimount.DeleteDevice(dp: Basedevice);
begin
  if dp.getDeviceName=Findidevice then begin
     Disconnect;
  end;
end;

procedure T_indimount.DeleteProperty(indiProp: IndiProperty);
begin
  { TODO :  check if a vital property is removed ? }
end;

procedure T_indimount.NewMessage(txt: string);
const k=2;
  blacklist: array[1..k] of string =('Timed guide','End Timed guide');
var ok: boolean;
    i: integer;
begin
  ok:=true;
  for i:=1 to k do begin
    if pos(blacklist[i],txt)>0 then ok:=false;
  end;
  if ok then begin
     if Assigned(FonMsg) then FonMsg(Findidevice+': '+txt);
  end else begin
    if Assigned(FonDeviceMsg) then FonDeviceMsg(Findidevice+': '+txt);
  end;
end;

procedure T_indimount.NewProperty(indiProp: IndiProperty);
var propname: string;
    proptype: INDI_TYPE;
begin
  propname:=indiProp.getName;
  proptype:=indiProp.getType;

  if (proptype=INDI_TEXT)and(propname='DEVICE_PORT') then begin
     Mountport:=indiProp.getText;
  end
  else if (proptype=INDI_SWITCH)and(propname='CONFIG_PROCESS') then begin
     configprop:=indiProp.getSwitch;
     configload:=IUFindSwitch(configprop,'CONFIG_LOAD');
     configsave:=IUFindSwitch(configprop,'CONFIG_SAVE');
     configdefault:=IUFindSwitch(configprop,'CONFIG_DEFAULT');
     if (configload=nil)or(configsave=nil)or(configdefault=nil) then configprop:=nil;
  end
  else if (proptype=INDI_NUMBER)and(propname='EQUATORIAL_EOD_COORD') then begin
      coord_prop:=indiProp.getNumber;
      coord_ra:=IUFindNumber(coord_prop,'RA');
      coord_dec:=IUFindNumber(coord_prop,'DEC');
      eod_coord:=true;
      if (coord_ra=nil)or(coord_dec=nil) then coord_prop:=nil;
   end
   else if (proptype=INDI_NUMBER)and(coord_prop=nil)and(propname='EQUATORIAL_COORD') then begin
      coord_prop:=indiProp.getNumber;
      coord_ra:=IUFindNumber(coord_prop,'RA');
      coord_dec:=IUFindNumber(coord_prop,'DEC');
      eod_coord:=false;
      if (coord_ra=nil)or(coord_dec=nil) then coord_prop:=nil;
   end
   else if (proptype=INDI_SWITCH)and(propname='ON_COORD_SET') then begin
      CoordSet:=indiProp.getSwitch;
      CoordSetTrack:=IUFindSwitch(CoordSet,'TRACK');
      CoordSetSlew:=IUFindSwitch(CoordSet,'SLEW');
      CoordSetSync:=IUFindSwitch(CoordSet,'SYNC');
   end
   else if (proptype=INDI_SWITCH)and(propname='TELESCOPE_PARK') then begin
      parkprop:=indiProp.getSwitch;
      swpark:=IUFindSwitch(parkprop,'PARK');
      swunpark:=IUFindSwitch(parkprop,'UNPARK');
      if (swpark=nil)or(swunpark=nil) then parkprop:=nil;
      if Assigned(FonParkChange) then FonParkChange(self);
   end
   else if (proptype=INDI_SWITCH)and(propname='TELESCOPE_ABORT_MOTION') then begin
      AbortmotionProp:=indiProp.getSwitch;
   end
   else if (proptype=INDI_NUMBER)and(propname='TELESCOPE_INFO') then begin
      TelescopeInfo:=indiProp.getNumber;
      TelescopeAperture:=IUFindNumber(TelescopeInfo,'TELESCOPE_APERTURE');
      TelescopeFocale:=IUFindNumber(TelescopeInfo,'TELESCOPE_FOCAL_LENGTH');
      if (TelescopeAperture=nil)or(TelescopeFocale=nil) then TelescopeInfo:=nil;
   end;
   CheckStatus;
end;

procedure T_indimount.NewNumber(nvp: INumberVectorProperty);
begin
  if nvp=coord_prop then begin
     if Assigned(FonCoordChange) then FonCoordChange(self);
  end;
end;

procedure T_indimount.NewText(tvp: ITextVectorProperty);
begin
//  writeln('NewText: '+tvp.name+' '+tvp.tp[0].text);
end;

procedure T_indimount.NewSwitch(svp: ISwitchVectorProperty);
begin
  if svp=parkprop then begin
     if Assigned(FonParkChange) then FonParkChange(self);
  end;
end;

procedure T_indimount.NewLight(lvp: ILightVectorProperty);
begin
//  writeln('NewLight: '+lvp.name);
end;

procedure T_indimount.SetPark(value:Boolean);
begin
if parkprop<>nil then begin
 IUResetSwitch(parkprop);
 if value then
    swpark.s:=ISS_ON
 else
    swunpark.s:=ISS_ON;
 indiclient.sendNewSwitch(parkprop);
 indiclient.WaitBusy(parkprop,120000);
end;
end;

function T_indimount.GetPark:Boolean;
begin
if parkprop<>nil then begin
  result:=(swpark.s=ISS_ON);
end
else result:=false;
end;

function  T_indimount.GetRA:double;
begin
if coord_prop<>nil then begin
  result:=coord_ra.value;
end
else result:=NullCoord;
end;

function  T_indimount.GetDec:double;
begin
if coord_prop<>nil then begin
  result:=coord_dec.value;
end
else result:=NullCoord;
end;

function  T_indimount.GetEquinox: double;
begin
 if eod_coord then result:=0
              else result:=2000;
end;

function  T_indimount.GetAperture:double;
begin
if TelescopeInfo<>nil then begin
  result:=TelescopeAperture.value;
end
else result:=-1;
end;

function  T_indimount.GetFocaleLength:double;
begin
if TelescopeInfo<>nil then begin
  result:=TelescopeFocale.value;
end
else result:=-1;
end;

function T_indimount.Slew(sra,sde: double):Boolean;
var waittime:integer;
begin
  result:=false;
  if (CoordSet<>nil) and (CoordSetTrack<>nil) and (coord_prop<>nil) then begin
    FMountSlewing:=true;
    IUResetSwitch(CoordSet);
    CoordSetTrack.s:=ISS_ON;
    indiclient.sendNewSwitch(CoordSet);
    if (15*abs(coord_ra.value-sra)+abs(coord_dec.value-sde))>0.5 then waittime:=120000 else waittime:=15000;
    coord_ra.value:=sra;
    coord_dec.value:=sde;
    indiclient.sendNewNumber(coord_prop);
    indiclient.WaitBusy(coord_prop,waittime);
    FMountSlewing:=false;
    result:=true;
  end;
end;

function T_indimount.Sync(sra,sde: double):Boolean;
begin
  result:=false;
  if (CoordSet<>nil) and (CoordSetSync<>nil) and (coord_prop<>nil) then begin
    IUResetSwitch(CoordSet);
    CoordSetSync.s:=ISS_ON;
    indiclient.sendNewSwitch(CoordSet);
    coord_ra.value:=sra;
    coord_dec.value:=sde;
    indiclient.sendNewNumber(coord_prop);
    indiclient.WaitBusy(coord_prop,5000);
    result:=true;
  end;
end;

function T_indimount.Track:Boolean;
var waittime:integer;
begin
  result:=false;
  if (CoordSet<>nil) and (CoordSetTrack<>nil) and (coord_prop<>nil) then begin
    IUResetSwitch(CoordSet);
    CoordSetTrack.s:=ISS_ON;
    indiclient.sendNewSwitch(CoordSet);
    indiclient.sendNewNumber(coord_prop);
    indiclient.WaitBusy(coord_prop);
    result:=true;
  end;
end;

procedure T_indimount.AbortMotion;
var ab: ISwitch;
begin
 if AbortmotionProp<>nil then begin
   ab:=IUFindSwitch(AbortmotionProp,'ABORT');
   if ab<>nil then begin
     ab.s:=ISS_ON;
     indiclient.sendNewSwitch(AbortmotionProp);
     msg('Stop telescope motion.');
   end;
 end;
end;

procedure T_indimount.SetTimeout(num:integer);
begin
 FTimeOut:=num;
 indiclient.Timeout:=FTimeOut;
end;

procedure T_indimount.LoadConfig;
begin
  if configprop<>nil then begin
    IUResetSwitch(configprop);
    configload.s:=ISS_ON;
    indiclient.sendNewSwitch(configprop);
  end;
end;

end.


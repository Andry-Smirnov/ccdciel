unit cu_ascomrestrotator;

{$mode objfpc}{$H+}

{
Copyright (C) 2019 Patrick Chevalley

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

uses cu_rotator, cu_ascomrest, u_global,
    u_translation, indiapi,
    Forms, ExtCtrls,Classes, SysUtils;

type
T_ascomrestrotator = class(T_rotator)
 private
   V: TAscomRest;
   stAngle: double;
   FInterfaceVersion: integer;
   StatusTimer: TTimer;
   procedure StatusTimerTimer(sender: TObject);
   function  Connected: boolean;
   function  InterfaceVersion: integer;
 protected
   procedure SetAngle(p:double); override;
   function  GetAngle:double; override;
   procedure SetTimeout(num:integer); override;
   function  GetDriverReverse:boolean; override;
   procedure SetDriverReverse(value:boolean); override;

   function  WaitRotatorMoving(maxtime:integer):boolean;
public
   constructor Create(AOwner: TComponent);override;
   destructor  Destroy; override;
   Procedure Connect(cp1: string; cp2:string=''; cp3:string=''; cp4:string=''; cp5:string=''; cp6:string='');  override;
   procedure Disconnect; override;
   Procedure Halt; override;
end;

const waitpoll=1000;
      statusinterval=3000;

implementation

constructor T_ascomrestrotator.Create(AOwner: TComponent);
begin
 inherited Create(AOwner);
 V:=TAscomRest.Create(self);
 V.ClientId:=3204;
 FRotatorInterface:=ASCOMREST;
 FInterfaceVersion:=1;
 StatusTimer:=TTimer.Create(nil);
 StatusTimer.Enabled:=false;
 StatusTimer.Interval:=statusinterval;
 StatusTimer.OnTimer:=@StatusTimerTimer;
end;

destructor  T_ascomrestrotator.Destroy;
begin
 StatusTimer.Free;
 inherited Destroy;
end;

function  T_ascomrestrotator.InterfaceVersion: integer;
begin
 result:=1;
  try
   result:=V.Get('interfaceversion').AsInt;
  except
    result:=1;
  end;
end;

procedure T_ascomrestrotator.Connect(cp1: string; cp2:string=''; cp3:string=''; cp4:string=''; cp5:string=''; cp6:string='');
begin
  try
  FStatus := devConnecting;
  FCalibrationAngle:=0;
  FReverse:=False;
  V.Host:=cp1;
  V.Port:=cp2;
  V.Protocol:=cp3;
  V.User:=cp5;
  V.Password:=cp6;
  Fdevice:=cp4;
  if Assigned(FonStatusChange) then FonStatusChange(self);
  V.Device:=Fdevice;
  V.Timeout:=2000;
  V.Put('connected',true);
  if V.Get('connected').AsBool then begin
     V.Timeout:=120000;
     FInterfaceVersion:=InterfaceVersion;
     try
     msg('Driver version: '+V.Get('driverversion').AsString,9);
     except
       msg('Error: unknown driver version',9);
     end;
     msg(rsConnected3);
     FStatus := devConnected;
     if Assigned(FonStatusChange) then FonStatusChange(self);
     StatusTimer.Enabled:=true;
  end
  else
     Disconnect;
  except
   on E: Exception do begin
      msg(Format(rsConnectionEr, [E.Message]),0);
      Disconnect;
   end;
  end;
end;

procedure T_ascomrestrotator.Disconnect;
begin
   StatusTimer.Enabled:=false;
   FStatus := devDisconnected;
   if Assigned(FonStatusChange) then FonStatusChange(self);
   try
     msg(rsDisconnected3,0);
     // the server is responsible for device disconnection
   except
     on E: Exception do msg(Format(rsDisconnectio, [E.Message]),0);
   end;
end;

function T_ascomrestrotator.Connected: boolean;
begin
result:=false;
  try
  result:=V.Get('connected').AsBool;
  except
   result:=false;
  end;
end;

procedure T_ascomrestrotator.StatusTimerTimer(sender: TObject);
var p: double;
begin
 StatusTimer.Enabled:=false;
 try
  if not Connected then begin
     FStatus := devDisconnected;
     if Assigned(FonStatusChange) then FonStatusChange(self);
     msg(rsDisconnected3,0);
  end
  else begin
    try
      p:=GetAngle;
      if p<>stAngle then begin
        stAngle:=p;
        if Assigned(FonAngleChange) then FonAngleChange(self);
      end;
     except
     on E: Exception do msg('Status error: ' + E.Message,0);
    end;
  end;
  finally
   if FStatus=devConnected then StatusTimer.Enabled:=true;
  end;
end;

function T_ascomrestrotator.WaitRotatorMoving(maxtime:integer):boolean;
var count,maxcount:integer;
begin
 result:=true;
 try
   maxcount:=maxtime div waitpoll;
   count:=0;
   while (V.Get('ismoving').AsBool)and(count<maxcount) do begin
      sleep(waitpoll);
      if GetCurrentThreadId=MainThreadID then Application.ProcessMessages;
      inc(count);
   end;
   result:=(count<maxcount);
 except
   result:=false;
 end;
end;

procedure T_ascomrestrotator.SetAngle(p:double);
begin
 try
   //msg('Rotator '+Fdevice+' move to internal '+FormatFloat(f1,p));
   V.Put('moveabsolute',['Position',FormatFloat(f2,p)]);
   WaitRotatorMoving(30000);

   except
    on E: Exception do msg('Error, can''t move to. ' + E.Message,0);
   end;
end;

function  T_ascomrestrotator.GetAngle:double;
begin
 result:=0;
 try
   result:=V.Get('position').AsInt;
 except
    on E: Exception do msg('Get position error: ' + E.Message,0);
 end;
end;

function T_ascomrestrotator.GetDriverReverse:boolean;
begin
 result:=false;
   try
   if V.Get('canreverse').AsBool then result:=V.Get('reverse').AsBool;
   except
    result:=false;
   end;
end;

procedure T_ascomrestrotator.SetDriverReverse(value:boolean);
begin
   try
   if V.Get('canreverse').AsBool then V.Put('reverse',value);
   except
   end;
end;

Procedure T_ascomrestrotator.Halt;
begin
   try
    V.Put('halt');
   except
    on E: Exception do msg('Halt error: ' + E.Message,0);
   end;
end;

procedure T_ascomrestrotator.SetTimeout(num:integer);
begin
 FTimeOut:=num;
end;

end.


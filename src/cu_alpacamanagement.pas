unit cu_alpacamanagement;

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
{
  Implement the ASCOM Alpaca Management and Discovery API
  https://ascom-standards.org
}

interface

uses cu_ascomrest, u_utils,
  httpsend, synautil, fpjson, jsonparser, blcksock, synsock,
  process, Forms, Dialogs, Classes, SysUtils;

const AlpacaCurrentVersion = 1;
      AlpacaDiscStr = 'alpaca discovery';
      AlpacaDiscPort = '32227';
      DiscoverTimeout = 1000;

Type
  TAlpacaDevice = record
    DeviceName, DeviceType, DeviceId: string;
    DeviceNumber: integer;
  end;
  TAlpacaDeviceList = array of TAlpacaDevice;
  TAlpacaServer = record
     ip,port,id: string;
     servername,manufacturer,version,location: string;
     apiversion, devicecount: integer;
     devices: TAlpacaDeviceList;
  end;
  TAlpacaServerList = array of TAlpacaServer;

var
    FClientId: integer = 1;
    FClientTransactionID: integer =0;
    FLastErrorCode: integer;
    FLastError: string;

function AlpacaDiscover: TAlpacaServerList;
function AlpacaDiscoverServer: TAlpacaServerList;
procedure AlpacaServerDescription(var srv:TAlpacaServer);
function AlpacaApiVersions(ip,port: string): IIntArray;
function AlpacaDevices(ip,port,apiversion: string):TAlpacaDeviceList;
procedure AlpacaServerSetup(srv: TAlpacaServer);
procedure AlpacaDeviceSetup(srv: TAlpacaServer; dev:TAlpacaDevice);

implementation

function AlpacaDiscover: TAlpacaServerList;
var apiversions: array of integer;
    i,j: integer;
begin
  result:=AlpacaDiscoverServer;
  for i:=0 to Length(result)-1 do begin
    result[i].apiversion:=-1;
    result[i].devicecount:=0;
    SetLength(result[i].devices,0);
    SetLength(apiversions,0);
    try
    apiversions:=AlpacaApiVersions(result[i].ip,result[i].port);
    for j:=0 to Length(apiversions) do begin
      if apiversions[i]=AlpacaCurrentVersion then result[i].apiversion:=AlpacaCurrentVersion;
    end;
    except
      result[i].apiversion:=1;
    end;
    if result[i].apiversion=AlpacaCurrentVersion then begin
      try
      AlpacaServerDescription(result[i]);
      result[i].devices:=AlpacaDevices(result[i].ip,result[i].port,IntToStr(result[i].apiversion));
      result[i].devicecount:=length(result[i].devices);
      except
        on E: Exception do ShowMessage('Alpaca server at '+result[i].ip+':'+result[i].port+' report: '+CRLF+ E.Message);
      end;
    end;
  end;
end;

function GetBroadcastAddrList: TStringList;
var
  AProcess: TProcess;
  s: string;
  sl: TStringList;
  i, n: integer;
  {$IFDEF WINDOWS}
  j: integer;
  ip,mask: string;
  b,b1,b2: byte;
  hasIP, hasMask: boolean;
  {$ENDIF}
begin
  Result:=TStringList.Create;
  sl:=TStringList.Create();
  {$IFDEF WINDOWS}
  AProcess:=TProcess.Create(nil);
  AProcess.Executable := 'ipconfig.exe';
  AProcess.Options := AProcess.Options + [poUsePipes, poNoConsole];
  try
    AProcess.Execute();
    Sleep(500); // poWaitOnExit not working as expected
    sl.LoadFromStream(AProcess.Output);
  finally
    AProcess.Free();
  end;
  hasIP:=false;
  hasMask:=false;
  for i:=0 to sl.Count-1 do
  begin
    if (Pos('IPv4', sl[i])>0) or (Pos('IP-', sl[i])>0) or (Pos('IP Address', sl[i])>0) then begin
      s:=sl[i];
      ip:=Trim(Copy(s, Pos(':', s)+1, 999));
      if Pos(':', ip)>0 then Continue; // TODO: IPv6
      hasIP:=true;
    end;
    if (Pos('Mask', sl[i])>0) then begin
      s:=sl[i];
      mask:=Trim(Copy(s, Pos(':', s)+1, 999));
      if Pos(':', mask)>0 then Continue; // TODO: IPv6
      hasMask:=true;
    end;
    if hasIP and hasMask then begin
      s:='';
      try
      for j:=1 to 4 do begin
        n:=pos('.',ip);
        if n=0 then b1:=strtoint(ip)
               else b1:=strtoint(copy(ip,1,n-1));
        delete(ip,1,n);
        n:=pos('.',mask);
        if n=0 then b2:=strtoint(mask)
               else b2:=strtoint(copy(mask,1,n-1));
        delete(mask,1,n);
        b:=b1 or (not b2);
        s:=s+inttostr(b)+'.';
      end;
      delete(s,length(s),1);
      Result.Add(Trim(s));
      except
      end;
      hasIP:=false;
      hasMask:=false;
    end;
  end;
  {$ENDIF}
  {$IFDEF UNIX}
  AProcess:=TProcess.Create(nil);
  AProcess.Executable := '/sbin/ifconfig';
  AProcess.Parameters.Add('-a');
  AProcess.Options := AProcess.Options + [poUsePipes, poWaitOnExit];
  try
    AProcess.Execute();
    sl.LoadFromStream(AProcess.Output);
  finally
    AProcess.Free();
  end;

  for i:=0 to sl.Count-1 do
  begin
    n:=Pos('broadcast ', sl[i]);
    if n=0 then Continue;
    s:=sl[i];
    s:=Copy(s, n+Length('broadcast '), 999);
    n:=Pos(' ', s);
    if n>0 then s:=Copy(s, 1, n);
    Result.Add(Trim(s));
  end;
  {$ENDIF}
  sl.Free();
end;

function AlpacaDiscoverServer: TAlpacaServerList;
var sock : TUDPBlockSocket;
    ip,port,id:string;
    data: array[0..1024] of char;
    p: pointer;
    i,n,k: integer;
    ok,duplicate: boolean;
    blist: TStringList;
    Fjson: TJSONData;
begin
  blist:=GetBroadcastAddrList;
  sock := TUDPBlockSocket.create;
  sock.enablebroadcast(true);
  setlength(result,0);
  k:=0;
  for n:=0 to blist.Count-1 do begin
    sock.Connect(blist[n], AlpacaDiscPort);
    data:=AlpacaDiscStr;
    p:=@data;
    sock.SendBuffer(p,length(AlpacaDiscStr));
    repeat
      ok:=sock.CanRead(DiscoverTimeout);
      if ok then begin
        sock.RecvBuffer(p,1024);
        ip:=''; port:=''; id:=''; duplicate:=false;
        {$IFDEF WINDOWS}
        for i:=0 to 3 do   // TODO: synapse or rtl bug?
        {$ELSE}
        for i:=1 to 4 do
        {$ENDIF}
          ip:=ip+inttostr(sock.RemoteSin.sin_addr.s_bytes[i])+'.';
        delete(ip,length(ip),1);
        Fjson:=GetJSON(data);
        if Fjson<>nil then begin
            port:=Fjson.GetPath('AlpacaPort').AsString;
            id:=Fjson.GetPath('AlpacaUniqueId').AsString;
        end;
        Fjson.Free;
        for i:=0 to Length(result)-1 do begin
          if result[i].id=id then duplicate:=true;
        end;
        if not duplicate then begin
          inc(k);
          SetLength(result,k);
          result[k-1].ip:=ip;
          result[k-1].port:=port;
          result[k-1].id:=id;
        end;
      end;
    until not ok;
  end;
  sock.Free;
  blist.Free;
end;

function ManagementGet(url:string; param: string=''):TAscomResult;
 var ok: boolean;
     i: integer;
     RESTRequest: THTTPthread;
 begin
   RESTRequest:=THTTPthread.Create;
   try
   RESTRequest.http.Document.Clear;
   RESTRequest.http.Headers.Clear;
   RESTRequest.http.Timeout:=DiscoverTimeout;
   if param>'' then begin
      url:=url+'?'+param+'&ClientID='+IntToStr(FClientId);
   end
   else begin
      url:=url+'?ClientID='+IntToStr(FClientId);
   end;
   inc(FClientTransactionID);
   url:=url+'&ClientTransactionID='+IntToStr(FClientTransactionID);
   RESTRequest.url:=url;
   RESTRequest.method:='GET';
   RESTRequest.Start;
   while not RESTRequest.Finished do begin
     sleep(100);
     if GetCurrentThreadId=MainThreadID then Application.ProcessMessages;
   end;
   ok := RESTRequest.ok;
   if ok then begin
     if (RESTRequest.http.ResultCode=200) then begin
       RESTRequest.http.Document.Position:=0;
       Result:=TAscomResult.Create;
       Result.data:=TJSONObject(GetJSON(RESTRequest.http.Document));
       try
       FLastErrorCode:=Result.GetName('ErrorNumber').AsInteger;
       FLastError:=Result.GetName('ErrorMessage').AsString;
       except
        FLastErrorCode:=0;
        FLastError:='Missing error message from server';
       end;
       if FLastErrorCode<>0 then begin
          Result.Free;
          raise EAscomException.Create(FLastError);
       end;
     end
     else begin
       FLastErrorCode:=RESTRequest.http.ResultCode;
       FLastError:=RESTRequest.http.ResultString;
       i:=pos('<br>',FLastError);
       if i>0 then FLastError:=copy(FLastError,1,i-1);
       raise EApiException.Create(FLastError);
     end;
   end
   else begin
     FLastErrorCode:=RESTRequest.http.Sock.LastError;
     FLastError:=RESTRequest.http.Sock.LastErrorDesc;
     raise ESocketException.Create(url+' '+FLastError);
   end;
   finally
     RESTRequest.Free;
   end;
 end;

procedure AlpacaServerDescription(var srv:TAlpacaServer);
var J: TAscomResult;
begin
  J:=ManagementGet('http://'+srv.ip+':'+srv.port+'/management/v'+IntToStr(srv.apiversion)+'/description');
  try
  with J.GetName('Value') do begin
    srv.servername:=GetPath('ServerName').AsString;
    srv.manufacturer:=GetPath('Manufacturer').AsString;
    srv.version:=GetPath('ManufacturerVersion').AsString;
    srv.location:=GetPath('Location').AsString;
  end;
  finally
    J.Free;
  end;
end;

function AlpacaApiVersions(ip,port: string): IIntArray;
begin
  result:=ManagementGet('http://'+ip+':'+port+'/management/apiversions').AsIntArray;
end;

function AlpacaDevices(ip,port,apiversion: string):TAlpacaDeviceList;
var J: TAscomResult;
    i,n: integer;
begin
  J:=ManagementGet('http://'+ip+':'+port+'/management/v'+apiversion+'/configureddevices');
  try
  with TJSONArray(J.GetName('Value')) do begin
    n:=Count;
    SetLength(Result,n);
    for i:=0 to n-1 do begin
      Result[i].DeviceName:=Objects[i].GetPath('DeviceName').AsString;
      Result[i].DeviceType:=Objects[i].GetPath('DeviceType').AsString;
      Result[i].DeviceNumber:=Objects[i].GetPath('DeviceNumber').AsInteger;
      Result[i].DeviceId:=Objects[i].GetPath('UniqueID').AsString;
    end;
  end;
  finally
    J.Free;
  end;
end;

procedure AlpacaServerSetup(srv: TAlpacaServer);
begin
  ExecuteFile('http://'+srv.ip+':'+srv.port+'/setup');
end;

procedure AlpacaDeviceSetup(srv: TAlpacaServer; dev:TAlpacaDevice);
begin
  ExecuteFile('http://'+srv.ip+':'+srv.port+'/setup/v'+IntToStr(srv.apiversion)+'/'+LowerCase(dev.DeviceType)+'/'+IntToStr(dev.DeviceNumber)+'/setup');
end;

end.

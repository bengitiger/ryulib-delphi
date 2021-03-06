{*
  Try this unit to avoid ABA problem when you want to use Lock-Free algorithm.
  LazyRelease will keep deleted objects and destroy it when you call Release() more than FRingSize times. 
  FRingSize will have 1024 as a default value.  If you want the deleted objects remain longer time, increase the size.  (LazyRelease := TLazyRelease.Create(Size you want);
*}
unit LazyRelease;

interface

uses
  DebugTools,
  Windows, SysUtils, Classes;

const
  DEFAULT_RING_SIZE = 1024;

type
  TReleaseEvent = procedure (Sender:TObject; AObject:pointer) of object;

  TPointerList = array of pointer;
  PPointerList = ^TPointerList;

  TLazyRelease = class
  private
    FCurrent : pointer;
    FIndex : integer;
    FRingSize : integer;
    FRing : PPointerList;
    FOnRelease: TReleaseEvent;
  public
    constructor Create(ARingSize:integer=DEFAULT_RING_SIZE); reintroduce;
    destructor Destroy; override;

    procedure Clear;
    procedure Release(AObj:pointer);

    property Current : pointer read FCurrent;
    property OnRelease : TReleaseEvent read FOnRelease write FOnRelease;
  end;

  TObjectList = array of TObject;
  PObjectList = ^TObjectList;

  TLazyDestroy = class
  private
    FCurrent : TObject;
    FIndex : integer;
    FRingSize : integer;
    FRing : PObjectList;
  public
    constructor Create(ARingSize:integer=DEFAULT_RING_SIZE); reintroduce;
    destructor Destroy; override;

    procedure Clear;
    procedure ClearCurrent;
    procedure Release(AObj:TObject);

    property Current : TObject read FCurrent;
  end;

implementation

{ TLazyRelease }

function CreatePointerList(ARingSize:integer):PPointerList;
var
  Loop: Integer;
begin
  New(Result);
  SetLength(Result^, ARingSize);
  for Loop := Low(Result^) to High(Result^) do Result^[Loop] := nil;
end;

procedure TLazyRelease.Clear;
var
  Loop: Integer;
  OldList, NewList : PPointerList;
begin
  NewList := CreatePointerList(FRingSize);

  OldList := InterlockedExchangePointer(Pointer(FRing), NewList);

  FIndex := 0;
  FCurrent := nil;

  if OldList <> nil then begin
    for Loop := Low(OldList^) to High(OldList^) do if OldList^[Loop] <> nil then FreeMem(OldList^[Loop]);
    Dispose(OldList);
  end;
end;

constructor TLazyRelease.Create(ARingSize:integer);
begin
  inherited Create;

  FRingSize := ARingSize;
  if FRingSize = 0 then FRingSize := DEFAULT_RING_SIZE;
 
  FIndex := 0;
  FCurrent := nil;

  FRing := CreatePointerList(FRingSize);
end;

destructor TLazyRelease.Destroy;
begin
  Clear;

  Dispose(FRing);

  inherited;
end;

procedure TLazyRelease.Release(AObj: pointer);
var
  Old : pointer;
  iIndex, iMod : integer;
begin
  FCurrent := AObj;

  iIndex := InterlockedIncrement(FIndex);
  if iIndex >= FRingSize then begin
    iMod := iIndex mod FRingSize;
    InterlockedCompareExchange(FIndex, iMod, iIndex);
  end else begin
    iMod := iIndex;
  end;

  Old := InterlockedExchangePointer(FRing^[iMod], AObj);

  if Old <> nil then
    try
        if Assigned(FOnRelease) then OnRelease(Self, Old)
        else FreeMem(Old);
    except
      on E : Exception do Trace('TLazyRelease.Release - ' + E.Message);
    end;
end;

{ TLazyDestroy }

function CreateObjectList(ARingSize:integer):PObjectList;
var
  Loop: Integer;
begin
  New(Result);
  SetLength(Result^, ARingSize);
  for Loop := Low(Result^) to High(Result^) do Result^[Loop] := nil;
end;

procedure TLazyDestroy.Clear;
var
  Loop: Integer;
  OldList, NewList : PObjectList;
begin
  NewList := CreateObjectList(FRingSize);

  OldList := InterlockedExchangePointer(Pointer(FRing), NewList);

  FIndex := 0;
  FCurrent := nil;

  if OldList <> nil then begin
    for Loop := Low(OldList^) to High(OldList^) do if OldList^[Loop] <> nil then OldList^[Loop].Free;
    Dispose(OldList);
  end;
end;

procedure TLazyDestroy.ClearCurrent;
begin
  FCurrent := nil;
end;

constructor TLazyDestroy.Create(ARingSize: integer);
begin
  inherited Create;

  FRingSize := ARingSize;
  if FRingSize = 0 then FRingSize := DEFAULT_RING_SIZE;

  FIndex := 0;
  FCurrent := nil;

  FRing := CreateObjectList(FRingSize);
end;

destructor TLazyDestroy.Destroy;
begin
  Clear;

  Dispose(FRing);

  inherited;
end;

procedure TLazyDestroy.Release(AObj: TObject);
var
  Old : TObject;
  iIndex, iMod : integer;
begin
  FCurrent := AObj;

  iIndex := InterlockedIncrement(FIndex);
  if iIndex >= FRingSize then begin
    iMod := iIndex mod FRingSize;
    InterlockedCompareExchange(FIndex, iMod, iIndex);
  end else begin
    iMod := iIndex;
  end;

  Old := InterlockedExchangePointer(Pointer(FRing^[iMod]), AObj);

  try
    if Old <> nil then Old.Free;
  except
    on E : Exception do Trace('TLazyDestroy.Release - ' + E.Message);
  end;
end;

end.

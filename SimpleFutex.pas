unit SimpleFutex;

{$IF Defined(LINUX) and Defined(FPC)}
  {$DEFINE Linux}
{$ELSE}
  {$MESSAGE FATAL 'Unsupported operating system.'}
{$IFEND}

{$IFDEF FPC}
  {$MODE ObjFPC}
{$ENDIF}
{$H+}

{$IFOPT Q+}
  {$DEFINE OverflowChecks}
{$ENDIF}

interface

uses
  SysUtils, UnixType,
  AuxTypes;

type
  ESFException = class(Exception);

  ESFTimeError  = class(ESFException);
  ESFFutexError = class(ESFException);

const
  INFINITE = UInt32(-1);

type
  TFutex = cInt;
  PFutex = ^TFutex;

{
  fwrWoken       - the waiting was ended by FUTEX_WAKE

  fwrValue       - value of futex did not match parameter Value at the time of
                   call

  fwrTimeout     - waiting timed out

  fwrInterrupted - waiting was interrupted by a signal or by a spurious wakeup
}
  TFutexWaitResult = (fwrWoken,fwrValue,fwrTimeout,fwrInterrupted);

Function FutexWaitIntr(var Futex: TFutex; Value: TFutex; Timeout: UInt32 = INFINITE): TFutexWaitResult;
Function FutexWait(var Futex: TFutex; Value: TFutex; Timeout: UInt32 = INFINITE): TFutexWaitResult;

Function FutexWake(var Futex: TFutex; Count: Integer): Integer;

Function FutexRequeue(var Futex: TFutex; Count: Integer; var Futex2: TFutex): Integer;
{
  When FutexRequeue returns any negative number, it indicates that Futex
  variable did not matched Value parameter at the time of call.
}
Function FutexCmpRequeue(var Futex: TFutex; Count: Integer; Value: TFutex; var Futex2: TFutex): Integer;

//------------------------------------------------------------------------------

procedure SimpleFutexInit(out Futex: TFutex);

procedure SimpleFutexLock(var Futex: TFutex);
procedure SimpleFutexUnlock(var Futex: TFutex);

//------------------------------------------------------------------------------

procedure SimpleSemaphoreInit(const Futex: TFutex; InitialCount: Integer);

//procedure SimpleSemaphoreWait(cout Futex: TFutex);
//procedure SimpleSemaphorePost(cout Futex: TFutex);

implementation

uses
  BaseUnix, Linux, Errors,
  InterlockedOps;

Function FutexWaitIntr(var Futex: TFutex; Value: TFutex; Timeout: UInt32 = INFINITE): TFutexWaitResult;
var
  ResVal:       cInt;
  TimeoutSpec:  TTimeSpec;
  ErrorNumber:  cInt;
begin
If Timeout <> INFINITE then
  begin
    TimeoutSpec.tv_sec := Timeout div 1000;
    TimeoutSpec.tv_nsec := (Timeout mod 1000) * 1000000;
    ResVal := Linux.Futex(@Futex,FUTEX_WAIT,Value,@TimeoutSpec);
  end
else ResVal := Linux.Futex(@Futex,FUTEX_WAIT,Value,nil);
If ResVal = -1 then
  begin
    // an error occurred
    ErrorNumber := errno;
    case ErrorNumber of
      ESysEWOULDBLOCK:  Result := fwrValue;
      ESysETIMEDOUT:    Result := fwrTimeout;
      ESysEINTR:        Result := fwrInterrupted;
    else
      // some other error
      raise ESFFutexError.CreateFmt('FutexWaitIntr: Error during waiting (%d - %s).',[ErrorNumber,StrError(ErrorNumber)]);
    end;
  end
else Result := fwrWoken;
end;

//------------------------------------------------------------------------------

{$IFDEF OverflowChecks}{$Q-}{$ENDIF}
Function FutexWait(var Futex: TFutex; Value: TFutex; Timeout: UInt32 = INFINITE): TFutexWaitResult;
var
  StartTime:  Int64;
  IntrTime:   Int64;

  Function GetTimeAsMilliseconds: Int64;
  var
    TimeSpec:     TTimeSpec;
    ErrorNumber:  cInt;
  begin
    If clock_gettime(CLOCK_MONOTONIC_RAW,@TimeSpec) <> 0 then
      begin
        ErrorNumber := errno;
        raise ESFTimeError.CreateFmt('FutexWait.GetTimeAsMilliseconds: Unable to obtain time (%d - %s).',[ErrorNumber,StrError(ErrorNumber)]);
      end
    else Result := (((Int64(TimeSpec.tv_sec) * 1000) + (Int64(TimeSpec.tv_nsec) div 1000000))) and (Int64(-1) shr 1);
  end;

begin
StartTime := GetTimeAsMilliseconds;
while True do
  begin
    Result := FutexWaitIntr(Futex,Value,Timeout);
    If Result = fwrInterrupted then
      begin
        // recalculate timeout, ignore time spent in here
        IntrTime := GetTimeAsMilliseconds;
        If IntrTime > StartTime then
          begin
            If Timeout <= (IntrTime - StartTime) then
              begin
                Result := fwrTimeout;
                Break{while};
              end
            else Timeout := Timeout - (IntrTime - StartTime)
          end;
      end
    else Break{while};
  end;
end;
{$IFDEF OverflowChecks}{$Q+}{$ENDIF}

//------------------------------------------------------------------------------

Function FutexWake(var Futex: TFutex; Count: Integer): Integer;
var
  ErrorNumber:  cInt;
begin
If Count < 0 then
  Result := Integer(Linux.Futex(@Futex,FUTEX_WAKE,cInt(MAXINT),nil))
else
  Result := Integer(Linux.Futex(@Futex,FUTEX_WAKE,cInt(Count),nil));
If Result = -1 then
  begin
    ErrorNumber := errno;
    raise ESFFutexError.CreateFmt('FutexWake: Waking failed (%d - %s).',[ErrorNumber,StrError(ErrorNumber)]);
  end;
end;

//------------------------------------------------------------------------------

Function FutexRequeue(var Futex: TFutex; Count: Integer; var Futex2: TFutex): Integer;
var
  ErrorNumber:  cInt;
begin
If Count < 0 then
  Result := Integer(Linux.Futex(@Futex,FUTEX_REQUEUE,cInt(MAXINT),nil,@Futex2,0))
else
  Result := Integer(Linux.Futex(@Futex,FUTEX_REQUEUE,cInt(Count),nil,@Futex2,0));
If Result = -1 then
  begin
    ErrorNumber := errno;
    raise ESFFutexError.CreateFmt('FutexRequeue: Requeue failed (%d - %s).',[ErrorNumber,StrError(ErrorNumber)]);
  end;
end;

//------------------------------------------------------------------------------

Function FutexCmpRequeue(var Futex: TFutex; Count: Integer; Value: TFutex; var Futex2: TFutex): Integer;
var
  ErrorNumber:  cInt;
begin
If Count < 0 then
  Result := Integer(Linux.Futex(@Futex,FUTEX_CMP_REQUEUE,cInt(MAXINT),nil,@Futex2,Value))
else
  Result := Integer(Linux.Futex(@Futex,FUTEX_CMP_REQUEUE,cInt(Count),nil,@Futex2,Value));
If Result = -1 then
  begin
    ErrorNumber := errno;
    If ErrorNumber = ESysEAGAIN then
      Result := -1
    else
      raise ESFFutexError.CreateFmt('FutexCmpRequeue: Requeue failed (%d - %s).',[ErrorNumber,StrError(ErrorNumber)]);
  end;
end;

//==============================================================================

const
  SF_STATE_UNLOCKED = 0;
  SF_STATE_LOCKED   = 1;
  SF_STATE_WAITERS  = -1;

//------------------------------------------------------------------------------

procedure SimpleFutexInit(out Futex: TFutex);
begin
Futex := SF_STATE_UNLOCKED;
end;

//------------------------------------------------------------------------------

procedure SimpleFutexLock(var Futex: TFutex);
var
  OrigState:  TFutex;
begin
{
  Check if futex is unlocked.

  If it is NOT, set state to locked.

  If it was locked or locked with waiters (ie. not unlocked), do nothing and
  leave the current state.
}
OrigState := InterlockedCompareExchange(Futex,SF_STATE_LOCKED,SF_STATE_UNLOCKED);
{
  If the original state was unlocked, just return because we now have lock with
  no waiter (state was set to locked).
}
If OrigState <> SF_STATE_UNLOCKED then
  begin
    // futex was locked or locked with waiters...
  {
    Check if there were waiters (OrigValue would be less than 0). If not, set
    state to locked with waiters because we will enter waiting.
  }
    If OrigState > SF_STATE_UNLOCKED then
      OrigState := InterlockedExchange(Futex,SF_STATE_WAITERS);
  {
    Wait in a loop until state of the futex becomes unlocked.

    Note that if we acquire lock here, the state of the futex will stay locked
    with waiter, even when there might be none. This is not problem, it just
    means there will be pointless call to FutexWake when unlocking
  }
    while OrigState <> SF_STATE_UNLOCKED do
      begin
        FutexWait(Futex,SF_STATE_WAITERS);
        // we don't know why the wait ended, so...
        OrigState := InterlockedExchange(Futex,SF_STATE_WAITERS);
      end;
  end;
end;

//------------------------------------------------------------------------------

procedure SimpleFutexUnlock(var Futex: TFutex);
begin
{
  Decrement the futex and check its original state.

  If it was other than locked, it means there were waiters (if we discount
  the possibility it being unlocked, which is an erroneous state at this point,
  but in that case no harm will be done, just a pointless call to FutexWake),
  so set it to unlocked and wake waiters.

  If it was in locked state, there is no waiter and we can just return.
}
If InterlockedDecrement(Futex) <> SF_STATE_LOCKED then
  begin
    InterlockedStore(Futex,SF_STATE_UNLOCKED);
  {
    Wake only one waiter, waking all is pointless because only one thread will
    be able to acquire the lock and others would just re-enter waiting.
  }
    FutexWake(Futex,1);
  end;
end;

//==============================================================================

procedure SimpleSemaphoreInit(const Futex: TFutex; InitialCount: Integer);
begin

end;

end.


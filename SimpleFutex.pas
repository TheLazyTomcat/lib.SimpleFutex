{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  Simple futex

    Main aim of this library is to provide wrappers for futexes (synchronization
    primitives in linux) and some very simple complete synchronization objects
    based on them - currently simple futex/mutex and semaphore are implemented.

      NOTE - since proper implementation of futexes is not particularly easy,
             there are probably errors. If you find any, please let me know.

  Version 1.0.2 (2022-02-26)

  Last change 2022-02-26

  ©2021-2022 František Milt

  Contacts:
    František Milt: frantisek.milt@gmail.com

  Support:
    If you find this code useful, please consider supporting its author(s) by
    making a small donation using the following link(s):

      https://www.paypal.me/FMilt

  Changelog:
    For detailed changelog and history please refer to this git repository:

      github.com/TheLazyTomcat/Lib.SimpleFutex

  Dependencies:
    AuxTypes       - github.com/TheLazyTomcat/Lib.AuxTypes
    AuxClasses     - github.com/TheLazyTomcat/Lib.AuxClasses
    InterlockedOps - github.com/TheLazyTomcat/Lib.InterlockedOps
  * SimpleCPUID    - github.com/TheLazyTomcat/Lib.SimpleCPUID

  SimpleCPUID might not be required, see library InterlockedOps for details.

===============================================================================}
unit SimpleFutex;

{$IF Defined(LINUX) and Defined(FPC)}
  {$DEFINE Linux}
{$ELSE}
  {$MESSAGE FATAL 'Unsupported operating system.'}
{$IFEND}

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$DEFINE FPC_DisableWarns}
  {$MACRO ON}
{$ENDIF}
{$H+}

{$IFOPT Q+}
  {$DEFINE OverflowChecks}
{$ENDIF}

interface

uses
  SysUtils, UnixType,
  AuxTypes, AuxClasses;

{===============================================================================
    Library-specific exceptions
===============================================================================}
type
  ESFException = class(Exception);

  ESFTimeError    = class(ESFException);
  ESFFutexError   = class(ESFException);
  ESFInvalidValue = class(ESFException);

{===============================================================================
--------------------------------------------------------------------------------
                                 Futex wrappers
--------------------------------------------------------------------------------
===============================================================================}
const
  INFINITE = UInt32(-1);

type
  TFutex = cInt;
  PFutex = ^TFutex;

{
  Values returned from waiting on futex.

    fwrWoken       - the waiting was ended by FUTEX_WAKE

    fwrValue       - value of futex did not match parameter Value at the time
                     of the call

    fwrTimeout     - waiting timed out

    fwrInterrupted - waiting was interrupted by a signal or by a spurious
                     wakeup
}
  TFutexWaitResult = (fwrWoken,fwrValue,fwrTimeout,fwrInterrupted);

{===============================================================================
    Futex wrappers - declaration
===============================================================================}
{
  FutexWaitIntr

  Waits on futex until the thread is woken by FUTEX_WAKE, signal, spurious
  wakeup or the timeout period elapses.

  If the parameter Value does not match content of the futex at the time of 
  call, the function returns immediately, returning fwrValue.

  What caused the function to return is indicated by returned value.
}
Function FutexWaitIntr(var Futex: TFutex; Value: TFutex; Timeout: UInt32 = INFINITE): TFutexWaitResult;

{
  FutexWait

  Behaves the same as FutexWaitIntr, but it will never return fwrInterrupted.
  If the waiting is ended by a cause that falls into that category, the
  function recalculates timeout in relation to already elapsed time and
  re-enters waiting.
}
Function FutexWait(var Futex: TFutex; Value: TFutex; Timeout: UInt32 = INFINITE): TFutexWaitResult;

{
  FutexWake

  Simple wrapper that wakes at most Count threads waiting on the given futex.

  If passed Count is negative, it will try to wake MAXINT (2147483647) threads.

  Returs number of woken waiters.
}
Function FutexWake(var Futex: TFutex; Count: Integer): Integer;

{
  FutexRequeue

  For description of requeue operation, refer to futex documentation.

  WakeCount is maximum number of woken waiters.

  RequeueCount is maximum number of requeued waiters.

  Returns sum of woken and requeued waiters.
}
Function FutexRequeue(var Futex: TFutex; var Futex2: TFutex; WakeCount,RequeueCount: Integer): Integer;

{
  FutexCmpRequeue

  For description of compare-requeue operation, refer to futex documentation.

  WakeCount gives maximum number of woken waiters.

  RequeueCount is maximum number of requeued waiters.

  When FutexCmpRequeue returns any negative number, it indicates that value of
  Futex variable did not match Value parameter at the time of call.
  Otherwise it returns a sum of woken and requeued waiters.
}
Function FutexCmpRequeue(var Futex: TFutex; Value: TFutex; var Futex2: TFutex; WakeCount,RequeueCount: Integer): Integer;

{===============================================================================
--------------------------------------------------------------------------------
                                  Simple futex
--------------------------------------------------------------------------------
===============================================================================}
{
  Simple futex behaves like a basic mutex or critical section - only one thread
  can lock it and no other thread can lock it again until it is unlocked.

  If the SF is locked, the SimpleFutexLock function will block until the SF is
  unlocked by other thread.

  Calling SimpleFutexUnlock on unlocked SF is permissible, but highly
  discouraged.

    WARNING - Simple futex is not recursive. Calling SimpleFutexLock on a
              locked mutex in the same thread will block indefinitely, creating
              a deadlock.

    WARNING - Simple futex is not robust. If a thread fails to unlock the SF,
              it will stay locked indefinitely (but note that it can be
              unlocked by any thread - SF is not a classical mutex with thread
              ownership).

    NOTE - Simple futex does not neeed to be explicitly initialized if it is
           set to all zero by other means (eg. memory initialization).
}
{===============================================================================
    Simple futex - declaration
===============================================================================}

procedure SimpleFutexInit(out Futex: TFutex);

procedure SimpleFutexLock(var Futex: TFutex);
procedure SimpleFutexUnlock(var Futex: TFutex);

{
  SimpleFutexQueue only sets the futex to a state indicating there are threads
  waiting on it.
  It is intended for a situation where you use Futex(Cmp)Requeue function to
  queue threads to wait on the Futex variable.
}
procedure SimpleFutexQueue(var Futex: TFutex);

{===============================================================================
--------------------------------------------------------------------------------
                                Simple semaphore
--------------------------------------------------------------------------------
===============================================================================}
{
  Only very basic implementation of semaphore (counter synchronizer).

  If count is greater than zero, it is signaled (unlocked). If zero, it is
  non-signaled (locked).

  SimpleSemaphoreWait decrements the count. If the count was zero or less
  before the call, it will enter waiting and blocks until the semaphore counter
  becomes positive again.

  SimpleSemaphorePost increments the count and wakes exactly one waiter, if any
  is present.

  Simple semaphore does not need to be initialized explicitly - it is enoug to
  set it to a positive integer or zero, which can be done eg. through memory
  initialization.
  But never set it to a negative value - in that case first call to
  SimpleSemaphoreWait will set it to zero and itself will block. Calling
  SimpleSemaphorePost on such semaphore will only increment the counter,
  nothing more.
}
{===============================================================================
    Simple semaphore - declaration
===============================================================================}

procedure SimpleSemaphoreInit(out Futex: TFutex; InitialCount: Integer);

procedure SimpleSemaphoreWait(var Futex: TFutex);
procedure SimpleSemaphorePost(var Futex: TFutex);

{===============================================================================
--------------------------------------------------------------------------------
                               TSimpleSynchronizer
--------------------------------------------------------------------------------
===============================================================================}
{
  Common ancestor class for wrappers around implemented simple synchronization
  primitives.

  Instance can either be created as standalone or as shared.

    Standalone instance is created by constructor that does not expect an
    external Futex variable. The futex is completely internal and is managet
    automatically. To properly use it, create one instance and use this one
    object in all synchronizing threads.

    Shared instace expects pre-existing futex variable to be passed to the
    constructor. This futex is then used for locking. To use this mode,
    allocate a futex variable and create new instance from this one futex for
    each synchronizing thread. Note that you are responsible for futex
    management (initialization, finalization).
}
{===============================================================================
    TSimpleSynchronizer - class declaration
===============================================================================}
type
  TSimpleSynchronizer = class(TCustomObject)
  protected
    fLocalFutex:  TFutex;
    fFutexPtr:    PFutex;
    fOwnsFutex:   Boolean;
    procedure Initialize(var Futex: TFutex); virtual;
    procedure Finalize; virtual;
  public
    constructor Create(var Futex: TFutex); overload; virtual;
    constructor Create; overload; virtual;
    destructor Destroy; override;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                  TSimpleFutex
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSimpleFutex - class declaration
===============================================================================}
type
  TSimpleFutex = class(TSimpleSynchronizer)
  protected
    procedure Initialize(var Futex: TFutex); override;
  public
    procedure Enter; virtual;
    procedure Leave; virtual;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                TSimpleSemaphore
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSimpleSemaphore - class declaration
===============================================================================}
type
  TSimpleSemaphore = class(TSimpleSynchronizer)
  protected
    fInitialCount:  Integer;
    procedure Initialize(var Futex: TFutex); override;
  public
    constructor CreateAndInitCount(InitialCount: Integer); overload; virtual;
    procedure Acquire; virtual;
    procedure Release; virtual;
  end;

implementation

uses
  BaseUnix, Linux, Errors,
  InterlockedOps;

{$IFDEF FPC_DisableWarns}
  {$DEFINE FPCDWM}
  {$DEFINE W4055:={$WARN 4055 OFF}} // Conversion between ordinals and pointers is not portable
{$ENDIF}

{===============================================================================
--------------------------------------------------------------------------------
                                 Futex wrappers
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Futex wrappers - implementation
===============================================================================}

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
while True do
  begin
    StartTime := GetTimeAsMilliseconds;
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

Function FutexRequeue(var Futex: TFutex; var Futex2: TFutex; WakeCount,RequeueCount: Integer): Integer;
var
  ErrorNumber:  cInt;
begin
{$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
Result := Integer(Linux.Futex(@Futex,FUTEX_REQUEUE,cInt(WakeCount),Pointer(PtrInt(RequeueCount)),@Futex2,0));
{$IFDEF FPCDWM}{$POP}{$ENDIF}
If Result = -1 then
  begin
    ErrorNumber := errno;
    raise ESFFutexError.CreateFmt('FutexRequeue: Requeue failed (%d - %s).',[ErrorNumber,StrError(ErrorNumber)]);
  end;
end;

//------------------------------------------------------------------------------

Function FutexCmpRequeue(var Futex: TFutex; Value: TFutex; var Futex2: TFutex; WakeCount,RequeueCount: Integer): Integer;
var
  ErrorNumber:  cInt;
begin
{$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
Result := Integer(Linux.Futex(@Futex,FUTEX_CMP_REQUEUE,cInt(WakeCount),Pointer(PtrInt(RequeueCount)),@Futex2,Value));
{$IFDEF FPCDWM}{$POP}{$ENDIF}
If Result = -1 then
  begin
    ErrorNumber := errno;
    If ErrorNumber = ESysEAGAIN then
      Result := -1
    else
      raise ESFFutexError.CreateFmt('FutexCmpRequeue: Requeue failed (%d - %s).',[ErrorNumber,StrError(ErrorNumber)]);
  end;
end;

{===============================================================================
--------------------------------------------------------------------------------
                                  Simple futex
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Simple futex - constants
===============================================================================}
const
  SF_STATE_UNLOCKED = 0;
  SF_STATE_LOCKED   = 1;
  SF_STATE_WAITERS  = -1;

{===============================================================================
    Simple futex - implementation
===============================================================================}

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
    with waiter, even when there might be none. This is not a problem, it just
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
  Decrement the futex and check its current state.

  If it is other than unlocked, it means there were waiters (if we discount
  the possibility that it was already unlocked, which is an erroneous state at
  this point, but in that case no harm will be done, just a pointless call to
  FutexWake), so set it to unlocked and wake waiters.

  If it is in an unlocked state, then there is no waiter and we can just return.
}
If InterlockedDecrement(Futex) <> SF_STATE_UNLOCKED then
  begin
    InterlockedStore(Futex,SF_STATE_UNLOCKED);
  {
    Wake only one waiter, waking all is pointless because only one thread will
    be able to acquire the lock and others would just re-enter waiting.
  }
    FutexWake(Futex,1);
  end;
end;

//------------------------------------------------------------------------------

procedure SimpleFutexQueue(var Futex: TFutex);
begin
InterlockedStore(Futex,SF_STATE_WAITERS);
end;

{===============================================================================
--------------------------------------------------------------------------------
                                Simple semaphore
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Simple semaphore - implementation
===============================================================================}

procedure SimpleSemaphoreInit(out Futex: TFutex; InitialCount: Integer);
begin
If InitialCount >= 0 then
  Futex := InitialCount
else
  raise ESFInvalidValue.CreateFmt('SimpleSemaphoreInit: Invalid initial count (%d).',[InitialCount]);
end;

//------------------------------------------------------------------------------

procedure SimpleSemaphoreWait(var Futex: TFutex);
var
  OldCount: TFutex;
begin
repeat
{
  Decrement the semaphore counter and if it was 0, enter waiting.

  If it was above zero, then just return since the semaphore was signaled.
}
  OldCount := InterlockedDecrementIfPositive(Futex);
  If OldCount < 0 then
    InterlockedStore(Futex,0)
  else If OldCount = 0 then
    FutexWait(Futex,OldCount - 1);
until OldCount > 0;
end;

//------------------------------------------------------------------------------

procedure SimpleSemaphorePost(var Futex: TFutex);
begin
{
  Always call FutexWake, since the increment will always increase the counter
  to a positive number.
}
InterlockedIncrement(Futex);
FutexWake(Futex,1);
end;

{===============================================================================
--------------------------------------------------------------------------------
                               TSimpleSynchronizer
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSimpleSynchronizer - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TSimpleSynchronizer - protected methods
-------------------------------------------------------------------------------}

procedure TSimpleSynchronizer.Initialize(var Futex: TFutex);
begin
fLocalFutex := 0;
fFutexPtr := @Futex;
fOwnsFutex := fFutexPtr = Addr(fLocalFutex);
end;

//------------------------------------------------------------------------------

procedure TSimpleSynchronizer.Finalize;
begin
// nothing to do atm.
end;

{-------------------------------------------------------------------------------
    TSimpleSynchronizer - public methods
-------------------------------------------------------------------------------}

constructor TSimpleSynchronizer.Create(var Futex: TFutex);
begin
inherited Create;
Initialize(Futex);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TSimpleSynchronizer.Create;
begin
inherited Create;
Initialize(fLocalFutex);
end;

//------------------------------------------------------------------------------

destructor TSimpleSynchronizer.Destroy;
begin
Finalize;
inherited;
end;

{===============================================================================
--------------------------------------------------------------------------------
                                  TSimpleFutex
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSimpleFutex - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TSimpleFutex - protected methods
-------------------------------------------------------------------------------}

procedure TSimpleFutex.Initialize(var Futex: TFutex);
begin
inherited;
If fOwnsFutex then
  SimpleFutexInit(fFutexPtr^);
end;

{-------------------------------------------------------------------------------
    TSimpleFutex - public methods
-------------------------------------------------------------------------------}

procedure TSimpleFutex.Enter;
begin
SimpleFutexLock(fFutexPtr^);
end;

//------------------------------------------------------------------------------

procedure TSimpleFutex.Leave;
begin
SimpleFutexUnlock(fFutexPtr^);
end;

{===============================================================================
--------------------------------------------------------------------------------
                                TSimpleSemaphore
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSimpleSemaphore - class declaration
===============================================================================}
{-------------------------------------------------------------------------------
    TSimpleSemaphore - protected methods
-------------------------------------------------------------------------------}

procedure TSimpleSemaphore.Initialize(var Futex: TFutex);
begin
inherited;
If fOwnsFutex then
  SimpleSemaphoreInit(fFutexPtr^,0);
end;

{-------------------------------------------------------------------------------
    TSimpleSemaphore - public methods
-------------------------------------------------------------------------------}

constructor TSimpleSemaphore.CreateAndInitCount(InitialCount: Integer);
begin
inherited Create;
SimpleSemaphoreInit(fFutexPtr^,InitialCount);
end;

//------------------------------------------------------------------------------

procedure TSimpleSemaphore.Acquire;
begin
SimpleSemaphoreWait(fFutexPtr^);
end;

//------------------------------------------------------------------------------

procedure TSimpleSemaphore.Release;
begin
SimpleSemaphorePost(fFutexPtr^);
end;

end.


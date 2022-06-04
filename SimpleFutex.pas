{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  Simple futex

    Main aim of this library is to provide wrappers for futexes (synchronization
    primitives in linux) and some very simple complete synchronization objects
    based on them - currently simple mutex and semaphore are implemented.

      NOTE - since proper implementation of futexes is not particularly easy,
             there are probably errors. If you find any, please let me know.

  Version 1.0.3 (2022-03-06)

  Last change 2022-03-06

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
{===============================================================================
    Futex wrappers - constants and types
===============================================================================}
const
  INFINITE = UInt32(-1);  // infinite timeout

  FUTEX_BITSET_MATCH_ANY = UInt32($FFFFFFFF); // the name says it all :P

type
  TFutexWord = cInt;
  PFutexWord = ^TFutexWord;

  TFutex = TFutexWord;
  PFutex = ^TFutex;

//------------------------------------------------------------------------------
{
  Values returned from waiting on futex.

    fwrWoken       - the waiting was ended by FUTEX_WAKE

    fwrValue       - value of futex did not match parameter Value at the time
                     of the call

    fwrTimeout     - waiting timed out

    fwrInterrupted - waiting was interrupted (eg. by a signal)
}
  TFutexWaitResult = (fwrWoken,fwrValue,fwrTimeout,fwrInterrupted);

{===============================================================================
    Futex wrappers - declaration
===============================================================================}
{
  FutexWait

  Waits on futex until the thread is woken by FUTEX_WAKE, signal, spurious
  wakeup or the timeout period elapses.

    If the parameter Value does not match content of the futex at the time of
    call, the function returns immediately, returning fwrValue.

    Setting Private to true indicates that the futex is used only withing
    current process and allows system to do some optimizations.

    When Realtime is true, the timing will use CLOCK_REALTIME clock instead of
    CLOCK_MONOTONIC. Supported only from Linux 4.5 up.

    What caused the function to return is indicated by returned value.

      WARNING - even when the function returns fwrWoken, it does not
                necessarily mean the waiter was explicitly woken, it might very
                well be a spurious wakeup.
}
Function FutexWait(var Futex: TFutexWord; Value: TFutexWord; Timeout: UInt32 = INFINITE; Private: Boolean = False; Realtime: Boolean = False): TFutexWaitResult;

{
  FutexWaitNoInt

  Behaves the same as FutexWaitIntr, but it will never return fwrInterrupted.
  If the waiting is ended by a cause that falls into that category, the
  function recalculates timeout in relation to already elapsed time and
  re-enters waiting.

    WARNING - do not use if the waiting can be requeued to a different futex.
              If the waiting is requeued and then is interrupted, this call
              will re-enter waiting on the original futex, not on the one
              to which it was requeued.
}
Function FutexWaitNoInt(var Futex: TFutexWord; Value: TFutexWord; Timeout: UInt32 = INFINITE; Private: Boolean = False; Realtime: Boolean = False): TFutexWaitResult;

{
  FutexWake

  Wakes at least one and at most Count threads waiting on the given futex.

    If passed Count is negative, it will try to wake MAXINT (2147483647)
    threads.

    Private indicates whether the futex is used only withing the current
    process.

    Returs number of woken waiters.
}
Function FutexWake(var Futex: TFutexWord; Count: Integer; Private: Boolean = False): Integer;

{
  FutexFD

  Creates a file descriptor that is associated with the futex.

    Value is used for asynchronous notification via signals (value stored here,
    when non-zero, denotes the signal number), for details refer to futex
    documentation.

    Private indicates whether the futex is used only withing the current
    process.

    Returs created file descriptor.

    WARNING - support for this call was removed in linux 2.6.26.
}
Function FutexFD(var Futex: TFutexWord; Value: Integer; Private: Boolean = False): Integer;

{
  FutexRequeue

  Requeues waiting from one futex (Futex) to another (Futex2).
  Please refer to futex documentation for detailed description of requeue
  operation.

    WakeCount is maximum number of woken waiters (any negative value is
    translated to MAXINT).

    RequeueCount is maximum number of requeued waiters (any negative value is
    translated to MAXINT).

    Private indicates whether the futex is used only withing the current
    process.

    Returns number of woken waiters.
}
Function FutexRequeue(var Futex: TFutexWord; var Futex2: TFutexWord; WakeCount,RequeueCount: Integer; Private: Boolean = False): Integer;

{
  FutexCmpRequeue

  Works the same as FutexRequeue, but it first checks whether Futex contains
  value passed in parameter Value. If not, then the function will immediately
  exit, returning a negative value.
  For detailed description of compare-requeue operation, refer to futex
  documentation.

    WakeCount gives maximum number of woken waiters (any negative value is
    translated to MAXINT).

    RequeueCount is maximum number of requeued waiters (any negative value is
    translated to MAXINT).

    Private indicates whether the futex is used only withing the current
    process.

    When FutexCmpRequeue returns any negative number, it indicates that value
    of Futex variable did not match Value parameter at the time of call.
    Otherwise it returns a sum of woken and requeued waiters.
}
Function FutexCmpRequeue(var Futex: TFutexWord; Value: TFutexWord; var Futex2: TFutexWord; WakeCount,RequeueCount: Integer; Private: Boolean = False): Integer;


Function FutexWaitBitSet(var Futex: TFutexWord; Value: TFutexWord; BitMask: UInt32 = FUTEX_BITSET_MATCH_ANY; Timeout: UInt32 = INFINITE; Private: Boolean = False; Realtime: Boolean = False): TFutexWaitResult;

Function FutexWaitBitSetNoInt(var Futex: TFutexWord; Value: TFutexWord; BitMask: UInt32 = FUTEX_BITSET_MATCH_ANY; Timeout: UInt32 = INFINITE; Private: Boolean = False; Realtime: Boolean = False): TFutexWaitResult;

Function FutexWakeBitSet(var Futex: TFutexWord; Count: Integer; BitMask: UInt32 = FUTEX_BITSET_MATCH_ANY; Private: Boolean = False): Integer;


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

procedure SimpleFutexInit(out Futex: TFutexWord);

procedure SimpleFutexLock(var Futex: TFutexWord);
procedure SimpleFutexUnlock(var Futex: TFutexWord);

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

procedure SimpleSemaphoreInit(out Futex: TFutexWord; InitialCount: Integer);

procedure SimpleSemaphoreWait(var Futex: TFutexWord);
procedure SimpleSemaphorePost(var Futex: TFutexWord);

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
    fLocalFutex:  TFutexWord;
    fFutexPtr:    PFutexWord;
    fOwnsFutex:   Boolean;
    procedure Initialize(var Futex: TFutexWord); virtual;
    procedure Finalize; virtual;
  public
    constructor Create(var Futex: TFutexWord); overload; virtual;
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
    procedure Initialize(var Futex: TFutexWord); override;
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
    procedure Initialize(var Futex: TFutexWord); override;
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
    Internals
===============================================================================}
const
  MSECS_PER_SEC = 1000;
  NSECS_PER_SEC = 1000000000;
  NSECS_PER_MSEC = 1000000;

{===============================================================================
    Futex system constants
===============================================================================}
const
  FUTEX_WAIT            = 0;
  FUTEX_WAKE            = 1;
  FUTEX_FD              = 2;  // removed in Linux 2.6.26
  FUTEX_REQUEUE         = 3;
  FUTEX_CMP_REQUEUE     = 4;
//FUTEX_WAKE_OP         = 5;
//FUTEX_LOCK_PI         = 6;
//FUTEX_UNLOCK_PI       = 7;
//FUTEX_TRYLOCK_PI      = 8;
  FUTEX_WAIT_BITSET     = 9;
  FUTEX_WAKE_BITSET     = 10;
//FUTEX_WAIT_REQUEUE_PI = 11;
//FUTEX_CMP_REQUEUE_PI  = 12;
//FUTEX_LOCK_PI2	      = 13; // since Linux 5.14

  FUTEX_PRIVATE_FLAG   = 128;
  FUTEX_CLOCK_REALTIME = 256;

//FUTEX_CMD_MASK = not cInt(FUTEX_PRIVATE_FLAG or FUTEX_CLOCK_REALTIME);

{===============================================================================
--------------------------------------------------------------------------------
                                 Futex wrappers
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Futex wrappers - internals
===============================================================================}

Function FutexOp(Op: cInt; Private: Boolean; Realtime: Boolean = False): cInt;
begin
Result := Op;
If Private then
  Result := Result or FUTEX_PRIVATE_FLAG;
If Realtime then
  Result := Result or FUTEX_CLOCK_REALTIME;
end;

//------------------------------------------------------------------------------

Function RectCount(Count: Integer): cInt;
begin
If Count < 0 then
  Result := cInt(MAXINT)
else
  Result := cInt(Count);
end;

//------------------------------------------------------------------------------

Function RectCountToPtr(Count: Integer): Pointer;
begin
{$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
If Count < 0 then
  Result := Pointer(PtrInt(MAXINT))
else
  Result := Pointer(PtrInt(cInt(Count)));
{$IFDEF FPCDWM}{$POP}{$ENDIF}
end;

//------------------------------------------------------------------------------

procedure GetTime(out Time: TTimeSpec; Realtime: Boolean);
var
  CallRes:      cInt;
  ErrorNumber:  cInt;
begin
If Realtime then
  CallRes := clock_gettime(CLOCK_REALTIME,@Time)
else
  CallRes := clock_gettime(CLOCK_MONOTONIC,@Time);
If CallRes <> 0 then
  begin
    ErrorNumber := errno;
    raise ESFTimeError.CreateFmt('FutexWait.GetTime: Unable to obtain time (%d - %s).',
      [ErrorNumber,StrError(ErrorNumber)]);
  end;
end;

//------------------------------------------------------------------------------

{$IFDEF OverflowChecks}{$Q-}{$ENDIF}
Function GetElapsedMillis(From: TTimeSpec; Realtime: Boolean): UInt32;
var
  CurrentTime:  TTimeSpec;
  Temp:         Int64;
begin
GetTime(CurrentTime,Realtime);
If CurrentTime.tv_sec >= From.tv_sec then // sanity check
  begin
    Temp := (((Int64(CurrentTime.tv_sec) - From.tv_sec) * MSECS_PER_SEC)  +
             ((Int64(CurrentTime.tv_nsec) - From.tv_nsec) div NSECS_PER_MSEC)) and
            (Int64(-1) shr 1);
    If Temp < INFINITE then
      Result := UInt32(Temp)
    else
      Result := INFINITE;
  end
else Result := 0;
end;
{$IFDEF OverflowChecks}{$Q+}{$ENDIF}

{===============================================================================
    Futex wrappers - implementation
===============================================================================}

Function FutexWait(var Futex: TFutexWord; Value: TFutexWord; Timeout: UInt32 = INFINITE; Private: Boolean = False; Realtime: Boolean = False): TFutexWaitResult;
var
  ResVal:       cInt;
  TimeoutSpec:  TTimeSpec;
  ErrorNumber:  cInt;
begin
If Timeout <> INFINITE then
  begin
    TimeoutSpec.tv_sec := Timeout div MSECS_PER_SEC;
    TimeoutSpec.tv_nsec := (Timeout mod MSECS_PER_SEC) * NSECS_PER_MSEC;
    ResVal := Linux.Futex(@Futex,FutexOp(FUTEX_WAIT,Private,Realtime),Value,@TimeoutSpec);
  end
else ResVal := Linux.Futex(@Futex,FutexOp(FUTEX_WAIT,Private,Realtime),Value,nil);
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
      raise ESFFutexError.CreateFmt('FutexWait: Wait failed (%d - %s).',
        [ErrorNumber,StrError(ErrorNumber)]);
    end;
  end
else Result := fwrWoken;
end;

//------------------------------------------------------------------------------

Function FutexWaitNoInt(var Futex: TFutexWord; Value: TFutexWord; Timeout: UInt32 = INFINITE; Private: Boolean = False; Realtime: Boolean = False): TFutexWaitResult;
var
  StartTime:        TTimeSpec;
  TimeoutRemaining: UInt32;
  ElapsedMillis:    UInt32;
begin
GetTime(StartTime,Realtime);
TimeoutRemaining := Timeout;
while True do
  begin
    Result := FutexWait(Futex,Value,TimeoutRemaining,Private,Realtime);
    If Result = fwrInterrupted then
      begin
        // no need to recalculate timeout if we are waiting for infinite period
        If Timeout <> INFINITE then
          begin
            // recalculate timeout, ignore time spent in recalculation
            ElapsedMillis := GetElapsedMillis(StartTime,Realtime);
            If ElapsedMillis > 0 then
              begin
                If Timeout <= ElapsedMillis then
                  begin
                    Result := fwrTimeout;
                    Break{while};
                  end
                else TimeoutRemaining := Timeout - ElapsedMillis;
              end;
          end;
      end
    else Break{while};
  end;
end;

//------------------------------------------------------------------------------

Function FutexWake(var Futex: TFutexWord; Count: Integer; Private: Boolean = False): Integer;
var
  ErrorNumber:  cInt;
begin
Result := Integer(Linux.Futex(@Futex,FutexOp(FUTEX_WAKE,Private),RectCount(Count),nil));
If Result = -1 then
  begin
    ErrorNumber := errno;
    raise ESFFutexError.CreateFmt('FutexWake: Waking failed (%d - %s).',
      [ErrorNumber,StrError(ErrorNumber)]);
  end;
end;

//------------------------------------------------------------------------------

Function FutexFD(var Futex: TFutexWord; Value: Integer; Private: Boolean = False): Integer;
var
  ErrorNumber:  cInt;
begin
Result := Integer(Linux.Futex(@Futex,FutexOp(FUTEX_FD,Private),cInt(Value),nil));
If Result = -1 then
  begin
    ErrorNumber := errno;
    raise ESFFutexError.CreateFmt('FutexFD: File descriptor creation failed (%d - %s).',
      [ErrorNumber,StrError(ErrorNumber)]);
  end;
end;

//------------------------------------------------------------------------------

Function FutexRequeue(var Futex: TFutexWord; var Futex2: TFutexWord; WakeCount,RequeueCount: Integer; Private: Boolean = False): Integer;
var
  ErrorNumber:  cInt;
begin
Result := Integer(Linux.Futex(@Futex,FutexOp(FUTEX_REQUEUE,Private),RectCount(WakeCount),RectCountToPtr(RequeueCount),@Futex2,0));
If Result = -1 then
  begin
    ErrorNumber := errno;
    raise ESFFutexError.CreateFmt('FutexRequeue: Requeue failed (%d - %s).',
      [ErrorNumber,StrError(ErrorNumber)]);
  end;
end;

//------------------------------------------------------------------------------

Function FutexCmpRequeue(var Futex: TFutexWord; Value: TFutexWord; var Futex2: TFutexWord; WakeCount,RequeueCount: Integer; Private: Boolean = False): Integer;
var
  ErrorNumber:  cInt;
begin
Result := Integer(Linux.Futex(@Futex,FutexOp(FUTEX_CMP_REQUEUE,Private),RectCount(WakeCount),RectCountToPtr(RequeueCount),@Futex2,Value));
If Result = -1 then
  begin
    ErrorNumber := errno;
    If ErrorNumber = ESysEAGAIN then
      Result := -1
    else
      raise ESFFutexError.CreateFmt('FutexCmpRequeue: Requeue failed (%d - %s).',
        [ErrorNumber,StrError(ErrorNumber)]);
  end;
end;

//------------------------------------------------------------------------------

Function FutexWaitBitSet(var Futex: TFutexWord; Value: TFutexWord; BitMask: UInt32 = FUTEX_BITSET_MATCH_ANY; Timeout: UInt32 = INFINITE; Private: Boolean = False; Realtime: Boolean = False): TFutexWaitResult;
var
  ResVal:       cInt;
  TimeoutSpec:  TTimeSpec;
  ErrorNumber:  cInt;
begin
If Timeout <> INFINITE then
  begin
    // timeout for FUTEX_WAIT_BITSET is absolute
    GetTime(TimeoutSpec,Realtime);
    TimeoutSpec.tv_sec := TimeoutSpec.tv_sec + time_t(Timeout div MSECS_PER_SEC);
    TimeoutSpec.tv_nsec := TimeoutSpec.tv_nsec + clong((Timeout mod MSECS_PER_SEC) * NSECS_PER_MSEC);
    If TimeoutSpec.tv_nsec > NSECS_PER_SEC then
      begin
        TimeoutSpec.tv_nsec := TimeoutSpec.tv_nsec - NSECS_PER_SEC;
        Inc(TimeoutSpec.tv_sec);
      end;
    ResVal := Linux.Futex(@Futex,FutexOp(FUTEX_WAIT_BITSET,Private,Realtime),Value,@TimeoutSpec,nil,cInt(BitMask));
  end
else ResVal := Linux.Futex(@Futex,FutexOp(FUTEX_WAIT_BITSET,Private,Realtime),Value,nil,nil,cInt(BitMask));
If ResVal = -1 then
  begin
    ErrorNumber := errno;
    case ErrorNumber of
      ESysEWOULDBLOCK:  Result := fwrValue;
      ESysETIMEDOUT:    Result := fwrTimeout;
      ESysEINTR:        Result := fwrInterrupted;
    else
      // some other error
      raise ESFFutexError.CreateFmt('FutexWaitBitSet: Wait failed (%d - %s).',
        [ErrorNumber,StrError(ErrorNumber)]);
    end;
  end
else Result := fwrWoken;
end;

//------------------------------------------------------------------------------

Function FutexWaitBitSetNoInt(var Futex: TFutexWord; Value: TFutexWord; BitMask: UInt32 = FUTEX_BITSET_MATCH_ANY; Timeout: UInt32 = INFINITE; Private: Boolean = False; Realtime: Boolean = False): TFutexWaitResult;
var
  StartTime:        TTimeSpec;
  TimeoutRemaining: UInt32;
  ElapsedMillis:    UInt32;
begin
GetTime(StartTime,Realtime);
TimeoutRemaining := Timeout;
while True do
  begin
    Result := FutexWaitBitSet(Futex,Value,BitMask,TimeoutRemaining,Private,Realtime);
    If Result = fwrInterrupted then
      begin
        If Timeout <> INFINITE then
          begin
            ElapsedMillis := GetElapsedMillis(StartTime,Realtime);
            If ElapsedMillis > 0 then
              begin
                If Timeout <= ElapsedMillis then
                  begin
                    Result := fwrTimeout;
                    Break{while};
                  end
                else TimeoutRemaining := Timeout - ElapsedMillis;
              end;
          end;
      end
    else Break{while};
  end;
end;

//------------------------------------------------------------------------------

Function FutexWakeBitSet(var Futex: TFutexWord; Count: Integer; BitMask: UInt32 = FUTEX_BITSET_MATCH_ANY; Private: Boolean = False): Integer;
var
  ErrorNumber:  cInt;
begin
Result := Integer(Linux.Futex(@Futex,FutexOp(FUTEX_WAKE_BITSET,Private),RectCount(Count),nil,nil,cInt(BitMask)));
If Result = -1 then
  begin
    ErrorNumber := errno;
    raise ESFFutexError.CreateFmt('FutexWakeBitSet: Waking failed (%d - %s).',
      [ErrorNumber,StrError(ErrorNumber)]);
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

procedure SimpleFutexInit(out Futex: TFutexWord);
begin
Futex := SF_STATE_UNLOCKED;
end;

//------------------------------------------------------------------------------

procedure SimpleFutexLock(var Futex: TFutexWord);
var
  OrigState:  TFutexWord;
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
  {
    Futex was locked or locked with waiters...

    Check if there were waiters (OrigValue would be less than 0). If not, set
    state to locked with waiters because we will enter waiting.
  }
    If OrigState > SF_STATE_UNLOCKED then
      OrigState := InterlockedExchange(Futex,SF_STATE_WAITERS);
  {
    Wait in a loop until state of the futex becomes unlocked.

    Note that if we acquire lock here, the state of the futex will stay locked
    with waiter, even when there might be none - this is not a problem.
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

procedure SimpleFutexUnlock(var Futex: TFutexWord);
begin
{
  Decrement the futex and check its current state.

  If it is other than unlocked, it means there were waiters (if we discount
  the possibility that it was already unlocked, which is an erroneous state at
  this point, but in that case no harm will be done). In any case set it to
  unlocked.
}
If InterlockedDecrement(Futex) <> SF_STATE_UNLOCKED then
  InterlockedStore(Futex,SF_STATE_UNLOCKED);
{
  Wake only one waiter, waking all is pointless because only one thread will
  be able to acquire the lock and others would just re-enter waiting.
}
FutexWake(Futex,1);
end;

{===============================================================================
--------------------------------------------------------------------------------
                                Simple semaphore
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Simple semaphore - implementation
===============================================================================}

procedure SimpleSemaphoreInit(out Futex: TFutexWord; InitialCount: Integer);
begin
If InitialCount >= 0 then
  Futex := InitialCount
else
  raise ESFInvalidValue.CreateFmt('SimpleSemaphoreInit: Invalid initial count (%d).',[InitialCount]);
end;

//------------------------------------------------------------------------------

procedure SimpleSemaphoreWait(var Futex: TFutexWord);
var
  OldCount: TFutexWord;
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

procedure SimpleSemaphorePost(var Futex: TFutexWord);
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

procedure TSimpleSynchronizer.Initialize(var Futex: TFutexWord);
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

constructor TSimpleSynchronizer.Create(var Futex: TFutexWord);
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

procedure TSimpleFutex.Initialize(var Futex: TFutexWord);
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

procedure TSimpleSemaphore.Initialize(var Futex: TFutexWord);
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


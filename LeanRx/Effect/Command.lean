import LeanRx.Effect.Model

namespace LeanRx.Effect

/-- Effects produced by a pure update. Constructors describe work as data;
execution belongs to a host interpreter after transaction commit. -/
inductive Cmd (Msg : Type) where
  | none
  | batch (commands : Array (Cmd Msg))
  | timeout (handle : Handle) (delayMs : UInt32) (message : Msg)
  | storageGet (handle : Handle) (key : String)
      (onResult : Except Error StorageResult → Msg)
  | storageSet (handle : Handle) (key value : String)
      (onResult : Except Error Unit → Msg)
  | http (handle : Handle) (request : HttpRequest)
      (onResult : Except Error HttpResponse → Msg)
  | foreign {ι ο : Type} (handle : Handle) (port : ForeignPort ι ο) (input : ι)
      (onResult : Except Error ο → Msg)
  | cancel (handle : Handle)

end LeanRx.Effect

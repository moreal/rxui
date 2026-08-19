import LeanRx

open LeanRx.Form

def invalid := submit { name := "Ada", age := "42" : RawForm }

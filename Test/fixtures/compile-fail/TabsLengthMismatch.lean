import LeanRx

open LeanRx

def invalid : TabsSpec 1 :=
  TabsSpec.create "Mismatched" #v["First", "Second"] #v["Only one panel"]

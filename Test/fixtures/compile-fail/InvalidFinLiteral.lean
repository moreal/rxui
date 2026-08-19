import LeanRx

open LeanRx

def invalid : TabsSpec 2 :=
  TabsSpec.createAt "Invalid literal"
    #v["First", "Second", "Third"] #v["One", "Two", "Three"]
    3 (by decide)

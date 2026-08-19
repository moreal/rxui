import LeanRx

open scoped LeanRxDsl

def bad : LeanRx.View .empty := jsx% <div rawHtml="<b>unsafe</b>"> []

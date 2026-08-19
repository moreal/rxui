import LeanRx

open scoped LeanRxDsl

def bad : LeanRx.View .empty := jsx% <button onDoubleClick="missing"> []

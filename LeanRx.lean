import LeanRx.Core.SourceInfo
import LeanRx.Core.Schema
import LeanRx.Core.Dependency
import LeanRx.Core.Store
import LeanRx.Core.RuntimeRep
import LeanRx.Core.Equality
import LeanRx.Core.Expr
import LeanRx.Proofs.DependencySound
import LeanRx.Graph.Model
import LeanRx.Graph.Build
import LeanRx.Graph.Topological
import LeanRx.Graph.Serialize
import LeanRx.Semantics.Store
import LeanRx.Semantics.Reference
import LeanRx.Semantics.Optimized
import LeanRx.Proofs.PropagationSound

/-! LeanRx's public library root. -/
namespace LeanRx

/-- The pinned implementation version. -/
def version : String := "0.1.0-dev"

end LeanRx

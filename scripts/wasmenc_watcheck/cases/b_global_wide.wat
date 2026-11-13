;; wasmenc watcheck case (generated skeleton, human-reviewed)
(module
  (import "env" "vitro_host_call" (func $host (param i32 i32) (result i64)))
  (memory 1 1)
  (global $g0 (mut i32) (i32.const 0))
  (global $g1 (mut i32) (i32.const 0))
  (global $g2 (mut i32) (i32.const 0))
  (global $g3 (mut i32) (i32.const 0))
  (global $g4 (mut i32) (i32.const 0))
  (global $g5 (mut i64) (i64.const 0))
  (func (export "main") (local i32 i32 i32 i64 f64 f32)

    ;; group: LoadGlobalD(0)
    block
      i32.const 4096
      f64.load
      drop
    end
    ;; group: StoreGlobalD(0)
    block
      f64.const 0
      local.set 4
      i32.const 4096
      local.get 4
      f64.store
    end
    ;; group: LoadGlobalQ(16)
    block
      i32.const 4112
      i64.load
      drop
    end
    ;; group: StoreGlobalQ(16)
    block
      i64.const 0
      local.set 3
      i32.const 4112
      local.get 3
      i64.store
    end
  )
)

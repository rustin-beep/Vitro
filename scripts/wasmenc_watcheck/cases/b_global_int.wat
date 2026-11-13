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

    ;; group: LoadGlobal(8)
    block
      i32.const 4104
      i32.load
      drop
    end
    ;; group: StoreGlobal(8)
    block
      i32.const 0
      local.set 0
      i32.const 4104
      local.get 0
      i32.store
    end
    ;; group: StoreGlobalByte(0)
    block
      i32.const 0
      local.set 0
      i32.const 4096
      local.get 0
      i32.store8
    end
    ;; group: LoadGlobalByte(0)
    block
      i32.const 4096
      i32.load8_s
      drop
    end
    ;; group: LoadGlobalUByte(0)
    block
      i32.const 4096
      i32.load8_u
      drop
    end
  )
)

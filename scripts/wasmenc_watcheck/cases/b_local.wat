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

    ;; group: LoadLocal(8)
    block
      global.get 1
      i32.const 8
      i32.add
      i32.load
      drop
    end
    ;; group: StoreLocal(8)
    block
      i32.const 0
      local.set 0
      global.get 1
      i32.const 8
      i32.add
      local.get 0
      i32.store
    end
    ;; group: LoadLocalD(8)
    block
      global.get 1
      i32.const 8
      i32.add
      f64.load
      drop
    end
    ;; group: StoreLocalD(8)
    block
      f64.const 0
      local.set 4
      global.get 1
      i32.const 8
      i32.add
      local.get 4
      f64.store
    end
    ;; group: LoadLocalQ(8)
    block
      global.get 1
      i32.const 8
      i32.add
      i64.load
      drop
    end
    ;; group: StoreLocalQ(8)
    block
      i64.const 0
      local.set 3
      global.get 1
      i32.const 8
      i32.add
      local.get 3
      i64.store
    end
  )
)

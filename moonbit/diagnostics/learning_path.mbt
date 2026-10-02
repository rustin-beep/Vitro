// M4 学习路径组装（learning_path.rs 照搬，2026-10-02）：检出误区 →
// 路径表查询 → 填运行时字段（target id/name 从检出误区带过——Rust
// d.pattern_id.clone() 同义）。无对应路径的误区跳过（filter_map）。

///|
/// 为检出的误区推荐学习路径（顺序 = 检出顺序——Rust into_iter 保序）。
pub fn recommend_learning_paths(
  detected : Array[DetectedMisconception],
) -> Array[LearningPath] {
  let table = default_paths()
  let out : Array[LearningPath] = []
  for d in detected {
    match table.get(d.pattern_id) {
      Some(p) => {
        // steps 防御性深拷（表数据共享引用会被消费者改写——陷阱 #30）
        let steps : Array[PathStep] = []
        for s in p.steps {
          let hl : Array[Int] = []
          for v in s.highlight_lines {
            hl.push(v)
          }
          steps.push(PathStep::{
            step_type: s.step_type,
            title: s.title,
            detail: s.detail,
            target_id: s.target_id,
            highlight_lines: hl,
          })
        }
        out.push(LearningPath::{
          target_misconception_id: d.pattern_id,
          target_misconception_name: d.pattern_name,
          estimated_time_minutes: p.estimated_time_minutes,
          steps,
        })
      }
      None => ()
    }
  }
  out
}

<script lang="ts">
  // 码表图标（2026-10-18 反馈③）：error_catalog 每条都带 icon id，真源是
  // moonbit/icons/<id>.svg（生成到 js/icons.ts）。运行期/编译期诊断卡与参考态
  // 码表共用本组件，保证「错误输出里能看到码表图标」。
  import { ICONS } from "../../js/icons.ts";

  let { icon = "", size = 20 }: { icon?: string; size?: number } = $props();
  const body = $derived(ICONS[icon] ?? ICONS["unknown-char"] ?? "");
</script>

<svg
  class="vr-codeicon"
  viewBox="0 0 24 24"
  width={size}
  height={size}
  fill="none"
  stroke="currentColor"
  stroke-width="1.8"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
>{@html body}</svg>

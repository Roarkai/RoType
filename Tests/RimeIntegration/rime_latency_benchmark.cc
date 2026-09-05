#include <algorithm>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>
#include <utility>
#include <rime_api.h>

void rime_require_module_lua();

int main(int argc, char** argv) {
  if (argc != 4) return 64;
  rime_require_module_lua();
  auto* api = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[2];
  traits.staging_dir = argv[3];
  traits.prebuilt_data_dir = argv[3];
  traits.app_name = "rime.rotype.latency-benchmark";
  traits.min_log_level = 3;
  traits.log_dir = "";
  api->setup(&traits);
  api->initialize(&traits);
  const auto session = api->create_session();
  if (!session || !api->select_schema(session, "rotype")) return 65;
  api->set_property(session, "rotype_translation_presentation", "panel");
  // Fixed public test inputs, never user text. No commits or frequency learning.
  for (const std::string input : {"shi", "nihao", "hello", "yingwenshu"}) {
    std::vector<double> samples;
    for (int iteration = 0; iteration < 25; ++iteration) {
      api->clear_composition(session);
      for (unsigned char key : input) {
        const auto start = std::chrono::steady_clock::now();
        api->process_key(session, key, 0);
        RIME_STRUCT(RimeContext, context);
        if (!api->get_context(session, &context)) return 66;
        if (context.menu.num_candidates > 5) return 67;
        api->free_context(&context);
        api->simulate_key_sequence(session, "{F19}");
        const double ms = std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - start).count();
        if (iteration >= 5) samples.push_back(ms); // warmup excluded
      }
    }
    std::sort(samples.begin(), samples.end());
    const auto percentile = [&](double fraction) {
      return samples[static_cast<size_t>((samples.size() - 1) * fraction)];
    };
    std::cout << std::fixed << std::setprecision(3) << "RIME " << input
              << " samples=" << samples.size() << " p50_ms=" << percentile(0.5)
              << " p95_ms=" << percentile(0.95) << '\n';
  }
  // Diagnostic corpus only: exact target visibility in page one, not a claim
  // about dictionary membership (an English echo may also match the target).
  const std::vector<std::pair<std::string, std::string>> vocabulary = {
      {"daima", "代码"}, {"huancun", "缓存"}, {"bushu", "部署"},
      {"xingnengyouhua", "性能优化"}, {"rengongzhineng", "人工智能"},
      {"qiyeweixin", "企业微信"}, {"luokeshurufa", "洛克输入法"}, {"yunyuansheng", "云原生"},
      {"computer", "computer"}, {"keyboard", "keyboard"}, {"cache", "cache"},
      {"server", "server"}, {"github", "GitHub"}, {"macos", "macOS"},
      {"typescript", "TypeScript"}, {"hello", "hello"}};
  for (const auto& [input, expected] : vocabulary) {
    api->clear_composition(session);
    api->simulate_key_sequence(session, input.c_str());
    RIME_STRUCT(RimeContext, context);
    if (!api->get_context(session, &context)) return 68;
    int rank = 0;
    std::string page;
    for (int i = 0; i < context.menu.num_candidates; ++i) {
      const std::string text = context.menu.candidates[i].text;
      if (text == expected && rank == 0) rank = i + 1;
      if (i) page += " | ";
      page += text;
    }
    api->free_context(&context);
    std::cout << "VOCAB\t" << input << '\t' << expected << "\trank=" << rank << '\t' << page << '\n';
  }
  api->destroy_session(session);
  api->finalize();
}

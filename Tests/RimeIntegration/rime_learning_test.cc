#include <chrono>
#include <iostream>
#include <string>
#include <thread>
#include <rime_api.h>

void rime_require_module_lua();

// Exercise the same public selection, F19 refresh and F20 submission paths as
// the controller. Each invocation is a new process; only its private user
// directory is shared with the next invocation.
struct Runtime {
  RimeApi* api;
  RimeSessionId session;
  std::string reading;
  ~Runtime() { api->destroy_session(session); api->finalize(); }

  std::string property(const char* name) {
    char buffer[16384] = {};
    return api->get_property(session, name, buffer, sizeof(buffer)) ? buffer : "";
  }

  void refresh() { api->simulate_key_sequence(session, "{F19}"); }

  void input() {
    api->clear_composition(session);
    for (char letter : reading) {
      api->process_key(session, letter, 0);
      refresh();
    }
  }

  int find(const std::string& target) {
    for (int page = 0; page < 4096; ++page) {
      RIME_STRUCT(RimeContext, context);
      if (!api->get_context(session, &context)) return -1;
      int rank = -1;
      for (int index = 0; index < context.menu.num_candidates; ++index) {
        if (target == context.menu.candidates[index].text)
          rank = context.menu.page_no * context.menu.page_size + index;
      }
      const bool last = context.menu.is_last_page;
      api->free_context(&context);
      if (rank >= 0) return rank;
      if (last) return -1;
      if (!api->change_page(session, false)) return -1;
      refresh();
    }
    std::cerr << "candidate traversal exceeded safety bound\n";
    std::exit(65);
  }

  bool consume(const std::string& expected) {
    RIME_STRUCT(RimeCommit, commit);
    if (!api->get_commit(session, &commit)) return false;
    const bool matches = expected == commit.text;
    api->free_commit(&commit);
    refresh();
    return matches;
  }

  bool select(const std::string& target) {
    input();
    const int rank = find(target);
    return rank >= 0 && api->select_candidate_on_current_page(session, rank % 5)
        && consume(target);
  }

  void finishTransaction() {
    // A real unhandled key ends Rime's short undo-learning window.
    api->simulate_key_sequence(session, "{Return}");
    refresh();
  }
};

int main(int argc, char** argv) {
  if (argc != 6) return 64;
  rime_require_module_lua();
  auto* api = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[2];
  traits.staging_dir = argv[3];
  traits.prebuilt_data_dir = argv[3];
  traits.app_name = "rime.rotype.learning-test";
  traits.min_log_level = 3;
  traits.log_dir = "";
  api->setup(&traits);
  api->initialize(&traits);
  Runtime runtime{api, api->create_session(),
                  std::string(argv[4]) == "rotype_flypy" ? "uijm" : "shijian"};
  if (!runtime.session || !api->select_schema(runtime.session, argv[4])) return 65;
  api->set_property(runtime.session, "rotype_translation_presentation", "panel");
  const std::string action = argv[5];
  const std::string preferred = "事件";
  const std::string original = "时间";

  if (action == "baseline" || action == "verify" || action == "verify-original") {
    runtime.input();
    const auto target = action == "verify-original" ? original : preferred;
    const int rank = runtime.find(target);
    std::cout << action << ": " << target << " rank=" << rank << '\n';
    if (action == "baseline") return rank > 0 ? 0 : 66;
    if (rank != 0) {
      std::cerr << "FAIL: expected learned preference at first visible candidate\n";
      return 42;
    }
    return 0;
  }

  if (action == "number" || action == "highlight-space") {
    runtime.input();
    const int rank = runtime.find(preferred);
    if (rank < 0) return 73;
    if (action == "number") {
      api->process_key(runtime.session, '1' + rank % 5, 0);
    } else {
      if (!api->highlight_candidate_on_current_page(runtime.session, rank % 5)) return 74;
      runtime.refresh();
      api->process_key(runtime.session, ' ', 0);
    }
    if (!runtime.consume(preferred)) return 75;
    runtime.finishTransaction();
    return 0;
  }

  if (action == "train" || action == "reverse" || action == "once" || action == "undo" || action == "late-undo") {
    const auto target = action == "reverse" ? original : preferred;
    const int repetitions = (action == "train" || action == "reverse") ? 3 : 1;
    for (int repeat = 0; repeat < repetitions; ++repeat) {
      if (!runtime.select(target)) return 67;
      if (action == "undo" || action == "late-undo") {
        if (action == "late-undo") std::this_thread::sleep_for(std::chrono::seconds(4));
        api->simulate_key_sequence(runtime.session, "{BackSpace}");
        runtime.refresh();
      } else {
        runtime.finishTransaction();
      }
    }
    std::cout << action << ": committed " << target << " x" << repetitions << '\n';
    return 0;
  }

  if (action == "forget") {
    runtime.input();
    const int rank = runtime.find(preferred);
    if (rank < 0) return 76;
    api->highlight_candidate_on_current_page(runtime.session, rank % 5);
    runtime.refresh();
    if (runtime.property("rotype_panel_can_forget") != "1") {
      std::cerr << "FAIL: learned candidate must expose the forget action\n";
      return 77;
    }
    if (!api->delete_candidate_on_current_page(runtime.session, rank % 5)) return 78;
    runtime.refresh();
    return 0;
  }

  if (action == "verify-forgotten") {
    runtime.input();
    if (runtime.find(original) != 0) return 79;
    runtime.input();
    const int rank = runtime.find(preferred);
    if (rank <= 0) return 80; // Factory word remains available, no longer promoted.
    if (!api->highlight_candidate_on_current_page(runtime.session, rank % 5)) return 81;
    runtime.refresh();
    if (runtime.property("rotype_panel_can_forget") != "0") return 82;
    std::cout << "forget removes the learned preference, not the factory word\n";
    return 0;
  }

  if (action == "translate") {
    runtime.input();
    const int rank = runtime.find(preferred);
    if (rank < 0 || !api->highlight_candidate_on_current_page(runtime.session, rank % 5)) return 68;
    runtime.refresh();
    if (runtime.property("rotype_panel_source") != preferred ||
        runtime.property("rotype_panel_scope") != "whole") return 69;
    for (const char* field : {"raw", "source", "identity", "scope"}) {
      const auto value = runtime.property((std::string("rotype_panel_") + field).c_str());
      api->set_property(runtime.session, (std::string("rotype_panel_commit_") + field).c_str(), value.c_str());
    }
    api->set_property(runtime.session, "rotype_panel_commit_text", "learning-sentinel");
    api->simulate_key_sequence(runtime.session, "{F20}");
    if (runtime.property("rotype_panel_committed") != "1" || !runtime.consume("learning-sentinel")) return 70;
    runtime.finishTransaction();
    return 0;
  }

  if (action == "verify-no-translation") {
    runtime.input();
    if (runtime.find("learning-sentinel") != -1) return 71;
    runtime.input();
    if (runtime.find(original) != 0) return 72;
    std::cout << "translation did not learn its output or promote its highlighted Chinese source\n";
    return 0;
  }
  return 64;
}

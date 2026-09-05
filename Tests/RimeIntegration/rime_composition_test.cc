#include <iostream>
#include <string>

#include <rime_api.h>

void rime_require_module_lua();

namespace {

std::string GetProperty(RimeApi* api, RimeSessionId session, const char* name) {
  char value[16384] = {};
  return api->get_property(session, name, value, sizeof(value)) ? value : "";
}

int FindCandidate(RimeApi* api, RimeSessionId session, const std::string& text) {
  RIME_STRUCT(RimeContext, context);
  if (!api->get_context(session, &context)) return -1;
  int found = -1;
  for (int index = 0; index < context.menu.num_candidates; ++index) {
    if (context.menu.candidates[index].text == text) found = index;
  }
  api->free_context(&context);
  return found;
}

bool ExpectCandidate(RimeApi* api,
                     RimeSessionId session,
                     int one_based_index,
                     const std::string& text,
                     const std::string& comment = "") {
  RIME_STRUCT(RimeContext, context);
  if (!api->get_context(session, &context)) return false;
  const int index = one_based_index - 1;
  const bool matches = index < context.menu.num_candidates &&
      context.menu.candidates[index].text == text &&
      (comment.empty() || context.menu.candidates[index].comment == comment);
  if (!matches) {
    std::cerr << "candidate " << one_based_index << " mismatch; candidates:\n";
    for (int i = 0; i < context.menu.num_candidates; ++i)
      std::cerr << i + 1 << ". " << context.menu.candidates[i].text << '\n';
  }
  api->free_context(&context);
  return matches;
}

bool CheckPanelPages(RimeApi* api, RimeSessionId session, const std::string& excluded_text) {
  for (int page = 0; page < 4096; ++page) {
    RIME_STRUCT(RimeContext, context);
    if (!api->get_context(session, &context)) return false;
    bool valid = context.menu.page_size == 5 && context.menu.num_candidates <= 5;
    for (int index = 0; index < context.menu.num_candidates; ++index)
      if (context.menu.candidates[index].text == excluded_text) valid = false;
    const bool last_page = context.menu.is_last_page;
    api->free_context(&context);
    if (!valid) { std::cerr << "invalid panel candidates on page " << page << '\n'; return false; }
    if (last_page) { std::cout << "panel pages checked: " << page + 1 << '\n'; return true; }
    if (!api->change_page(session, false)) { std::cerr << "panel paging stopped on page " << page << '\n'; return false; }
  }
  std::cerr << "panel candidate check exceeded 4096 pages\n";
  return false;
}

bool SubmitPanelText(RimeApi* api, RimeSessionId session, const std::string& text) {
  for (const char* field : {"raw", "source", "identity", "scope"}) {
    const auto value = GetProperty(api, session, (std::string("rotype_panel_") + field).c_str());
    api->set_property(session, (std::string("rotype_panel_commit_") + field).c_str(), value.c_str());
  }
  api->set_property(session, "rotype_panel_commit_text", text.c_str());
  api->simulate_key_sequence(session, "{F20}");
  return GetProperty(api, session, "rotype_panel_committed") == "1";
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 4) return 64;
  rime_require_module_lua();

  RimeApi* api = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[2];
  traits.staging_dir = argv[3];
  traits.prebuilt_data_dir = argv[3];
  traits.app_name = "rime.rotype.composition-test";
  traits.min_log_level = 3;
  traits.log_dir = "";
  api->setup(&traits);
  api->initialize(&traits);

  RimeSessionId session = api->create_session();
  if (!session || !api->select_schema(session, "rotype")) return 65;
  api->set_property(session, "rotype_translation_presentation", "panel");
  if (!api->simulate_key_sequence(session, "yingwenshu")) return 66;

  const int english_index = FindCandidate(api, session, "英文");
  if (english_index < 0 || !api->select_candidate_on_current_page(session, english_index)) return 67;

  api->simulate_key_sequence(session, "{F19}");
  const std::string source = "英文书";
  if (GetProperty(api, session, "rotype_panel_raw") != "yingwenshu" ||
      GetProperty(api, session, "rotype_panel_source") != source ||
      GetProperty(api, session, "rotype_panel_scope") != "whole") {
    std::cerr << "translation properties do not contain the full composition\n";
    return 68;
  }

  RIME_STRUCT(RimeContext, first_page);
  if (!api->get_context(session, &first_page)) return 71;
  const bool five_per_page = first_page.menu.page_size == 5 && first_page.menu.num_candidates <= 5;
  api->free_context(&first_page);
  if (!five_per_page) return 71;
  if (!SubmitPanelText(api, session, "English book")) return 73;

  RIME_STRUCT(RimeCommit, commit);
  if (!api->get_commit(session, &commit)) return 74;
  const bool committed_full_translation = std::string(commit.text) == "English book";
  if (!committed_full_translation)
    std::cerr << "unexpected translation commit: " << commit.text << '\n';
  api->free_commit(&commit);
  if (!api->simulate_key_sequence(session, "chuangkoule")) return 76;
  RIME_STRUCT(RimeContext, second_context);
  if (!api->get_context(session, &second_context)) return 77;
  api->free_context(&second_context);
  api->simulate_key_sequence(session, "{F19}");
  const std::string second_source = GetProperty(api, session, "rotype_panel_source");
  if (GetProperty(api, session, "rotype_panel_raw") != "chuangkoule" ||
      second_source == "le" || second_source == "了" || second_source.empty()) {
    std::cerr << "multi-syllable source was overwritten by the final segment\n";
    return 78;
  }

  api->clear_composition(session);
  api->set_property(session, "rotype_translation_presentation", "panel");

  // The static result uses exactly the same validated commit path as dynamic
  // text. It must confirm only the selected word, not consume the suffix.
  api->simulate_key_sequence(session, "yingwenshu");
  const int partial_index = FindCandidate(api, session, "英文");
  if (partial_index < 0) return 90;
  api->highlight_candidate_on_current_page(session, partial_index);
  api->simulate_key_sequence(session, "{F19}");
  if (GetProperty(api, session, "rotype_panel_source") != "英文" ||
      GetProperty(api, session, "rotype_panel_scope") != "segment") return 91;
  if (!SubmitPanelText(api, session, "English")) return 92;
  RIME_STRUCT(RimeCommit, premature);
  if (api->get_commit(session, &premature)) { api->free_commit(&premature); return 93; }
  RIME_STRUCT(RimeContext, partial_context);
  if (!api->get_context(session, &partial_context)) return 94;
  const bool prefix_retained = partial_context.commit_text_preview &&
      std::string(partial_context.commit_text_preview).find("English") == 0;
  api->free_context(&partial_context);
  if (!prefix_retained || std::string(api->get_input(session)) != "yingwenshu") return 95;
  api->clear_composition(session);

  for (const auto& schema : {std::string("rotype"), std::string("rotype_flypy")}) {
    const auto static_session = api->create_session();
    if (!static_session || !api->select_schema(static_session, schema.c_str())) return 96;
    api->set_property(static_session, "rotype_translation_presentation", "panel");
    api->simulate_key_sequence(static_session, schema == "rotype" ? "nihao" : "nihc");
    const int greeting_index = FindCandidate(api, static_session, "你好");
    if (greeting_index < 0) {
      std::cerr << "missing greeting for " << schema << '\n';
      ExpectCandidate(api, static_session, 1, "你好");
      return 97;
    }
    if (!CheckPanelPages(api, static_session, "hello")) return 103;
    // Restore the absolute first-page index after checking every candidate page.
    // Highlight returns false when unchanged; inspect the published selection.
    api->highlight_candidate(static_session, greeting_index);
    api->simulate_key_sequence(static_session, "{F19}");
    if (GetProperty(api, static_session, "rotype_panel_source") != "你好" ||
        GetProperty(api, static_session, "rotype_panel_scope") != "whole") return 98;
    if (!SubmitPanelText(api, static_session, "hello")) return 99;
    RIME_STRUCT(RimeCommit, greeting_commit);
    if (!api->get_commit(static_session, &greeting_commit)) return 100;
    const bool greeting_ok = std::string(greeting_commit.text) == "hello";
    api->free_commit(&greeting_commit);
    api->destroy_session(static_session);
    if (!greeting_ok) return 101;
  }
  api->set_property(session, "rotype_translation_presentation", "panel");
  api->simulate_key_sequence(session, "nihao");
  api->simulate_key_sequence(session, "{F19}");
  const auto first_identity = GetProperty(api, session, "rotype_panel_identity");
  if (first_identity.empty()) return 80;
  if (!api->highlight_candidate_on_current_page(session, 1)) return 81;
  api->simulate_key_sequence(session, "{F19}");
  if (GetProperty(api, session, "rotype_panel_identity") == first_identity) return 82;
  if (!api->change_page(session, false)) return 83;
  api->simulate_key_sequence(session, "{F19}");
  const auto page_identity = GetProperty(api, session, "rotype_panel_identity");
  const auto page_source = GetProperty(api, session, "rotype_panel_source");
  if (page_identity.empty() || page_identity == first_identity || page_source.empty()) return 84;
  if (!SubmitPanelText(api, session, "Second page translation")) return 85;
  RIME_STRUCT(RimeCommit, panel_commit);
  if (api->get_commit(session, &panel_commit)) {
    const bool panel_committed = std::string(panel_commit.text) == "Second page translation";
    api->free_commit(&panel_commit);
    if (!panel_committed) return 86;
  } else {
    RIME_STRUCT(RimeContext, remaining);
    if (!api->get_context(session, &remaining)) return 87;
    const bool retained_segment = remaining.commit_text_preview &&
        std::string(remaining.commit_text_preview).find("Second page translation") == 0;
    api->free_context(&remaining);
    if (!retained_segment || std::string(api->get_input(session)) != "nihao") return 88;
  }

  api->destroy_session(session);

  // Both Shift keys must enter persistent English, including from composition.
  // The inherited inline_ascii binding used to switch back after submission.
  const char* shift_schemes[][2] = {{"rotype", "nihao"}, {"rotype_flypy", "nihk"}};
  for (const auto& sample : shift_schemes) {
    const auto shift_session = api->create_session();
    if (!shift_session || !api->select_schema(shift_session, sample[0])) return 190;
    api->set_property(shift_session, "rotype_translation_presentation", "panel");
    for (int key : {0xffe1, 0xffe2}) { // X11 Shift_L / Shift_R
      api->clear_composition(shift_session);
      api->set_option(shift_session, "ascii_mode", false);
      api->simulate_key_sequence(shift_session, sample[1]);
      api->process_key(shift_session, key, 1); // press with Shift mask
      // The native controller refreshes the translation snapshot on flagsChanged.
      api->simulate_key_sequence(shift_session, "{F19}");
      api->process_key(shift_session, key, 1 << 30); // release
      if (!api->get_option(shift_session, "ascii_mode")) {
        std::cerr << "FAIL: internal F19 snapshot cancelled Shift gesture: " << sample[0] << '\n';
        return 191;
      }
      api->commit_composition(shift_session);
      if (!api->get_option(shift_session, "ascii_mode")) {
        std::cerr << "FAIL: Shift English mode reset after submission: " << sample[0] << ' ' << key << '\n';
        return 192;
      }
      api->process_key(shift_session, key, 1);
      api->simulate_key_sequence(shift_session, "{F19}");
      api->process_key(shift_session, key, 1 << 30);
      if (api->get_option(shift_session, "ascii_mode")) return 193;
      // Shift+letter must not toggle the mode on release.
      api->process_key(shift_session, key, 1);
      api->process_key(shift_session, 'A', 1);
      api->process_key(shift_session, key, 1 << 30);
      if (api->get_option(shift_session, "ascii_mode")) return 194;
    }
    api->destroy_session(shift_session);
  }
  std::cout << "persistent Shift switching and capital-letter chords passed\n";

  // Old schema imports load without restoring numbered translations or refresh.
  const auto legacy_session = api->create_session();
  if (!legacy_session || !api->select_schema(legacy_session, "rotype_compat")) return 104;
  api->simulate_key_sequence(legacy_session, "nihao");
  api->simulate_key_sequence(legacy_session, "{F18}");
  if (std::string(api->get_input(legacy_session)) != "nihao") return 105;
  if (!CheckPanelPages(api, legacy_session, "hello")) return 106;
  api->highlight_candidate(legacy_session, 0);
  const int legacy_greeting = FindCandidate(api, legacy_session, "你好");
  if (legacy_greeting < 0 || !api->select_candidate_on_current_page(legacy_session, legacy_greeting)) return 107;
  RIME_STRUCT(RimeCommit, legacy_commit);
  if (!api->get_commit(legacy_session, &legacy_commit)) return 108;
  const bool legacy_ok = std::string(legacy_commit.text) == "你好";
  api->free_commit(&legacy_commit);
  if (!legacy_ok) return 109;
  api->destroy_session(legacy_session);
  api->finalize();
  return committed_full_translation ? 0 : 75;
}

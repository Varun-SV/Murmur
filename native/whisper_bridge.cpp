#include "whisper_bridge.h"
#include "whisper.h" // found via target_include_directories → whisper_cpp/include/

#include <android/log.h>
#include <cmath>
#include <cstring>
#include <string>

#define LOG_TAG "WhisperBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,    LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR,   LOG_TAG, __VA_ARGS__)

struct WhisperContext {
    whisper_context* wctx;
};

WhisperContext* whisper_bridge_init(const char* model_path) {
    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false; // No GPU Whisper inference on Android in Phase 1

    whisper_context* wctx = whisper_init_from_file_with_params(model_path, cparams);
    if (!wctx) {
        LOGE("whisper_init_from_file_with_params failed for path: %s", model_path);
        return nullptr;
    }

    LOGI("Model loaded from %s", model_path);
    WhisperContext* ctx = new WhisperContext();
    ctx->wctx = wctx;
    return ctx;
}

void whisper_bridge_free(WhisperContext* ctx) {
    if (ctx) {
        whisper_free(ctx->wctx);
        delete ctx;
    }
}

int whisper_bridge_transcribe(
    WhisperContext* ctx,
    const float*    pcm_f32,
    int             n_samples,
    char*           out_text,
    char*           out_lang,
    float*          out_confidence
) {
    if (!ctx) return -2;

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_progress   = false;
    params.print_special    = false;
    params.print_realtime   = false;
    params.print_timestamps = false;
    params.language         = "auto";
    params.n_threads        = 4; // Sweet spot on arm64 for speed vs battery

    int rc = whisper_full(ctx->wctx, params, pcm_f32, n_samples);
    if (rc != 0) {
        LOGE("whisper_full returned %d", rc);
        return -1;
    }

    // Collect all segment text
    std::string text;
    int n_segs = whisper_full_n_segments(ctx->wctx);
    for (int i = 0; i < n_segs; ++i) {
        const char* seg = whisper_full_get_segment_text(ctx->wctx, i);
        if (seg) text += seg;
    }
    strncpy(out_text, text.c_str(), 4095);
    out_text[4095] = '\0';

    // Language
    int lang_id = whisper_full_lang_id(ctx->wctx);
    const char* lang = whisper_lang_str(lang_id);
    strncpy(out_lang, lang ? lang : "en", 15);
    out_lang[15] = '\0';

    // Confidence: geometric mean of token probabilities across all segments
    float log_sum = 0.0f;
    int   token_count = 0;
    for (int i = 0; i < n_segs; ++i) {
        int n_tok = whisper_full_n_tokens(ctx->wctx, i);
        for (int j = 0; j < n_tok; ++j) {
            float p = whisper_full_get_token_p(ctx->wctx, i, j);
            if (p > 0.0f) {
                log_sum += std::log(p);
                ++token_count;
            }
        }
    }
    *out_confidence = (token_count > 0) ? std::exp(log_sum / token_count) : 0.0f;

    LOGI("Transcribed %d segments, lang=%s, conf=%.2f", n_segs, out_lang, *out_confidence);
    return 0;
}

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WhisperContext WhisperContext;

/**
 * Load a whisper.cpp GGML model from disk.
 * Returns NULL on failure (file not found, corrupt model, OOM).
 * The caller owns the returned context and must free it with whisper_bridge_free().
 */
WhisperContext* whisper_bridge_init(const char* model_path);

/**
 * Release all resources held by the context.
 */
void whisper_bridge_free(WhisperContext* ctx);

/**
 * Transcribe normalized float32 PCM (16 kHz, mono).
 *
 * @param ctx            Context from whisper_bridge_init. Must not be NULL.
 * @param pcm_f32        PCM samples normalised to [-1.0, 1.0].
 * @param n_samples      Number of float samples.
 * @param out_text       Caller-allocated buffer of at least 4096 bytes. NUL-terminated.
 * @param out_lang       Caller-allocated buffer of at least 16 bytes. ISO 639-1 code, NUL-terminated.
 * @param out_confidence Pointer to a float. Set to geometric-mean token probability in [0, 1].
 *
 * @return 0 on success, negative on error:
 *         -1  whisper_full() failed
 *         -2  ctx is NULL
 */
int whisper_bridge_transcribe(
    WhisperContext* ctx,
    const float*    pcm_f32,
    int             n_samples,
    char*           out_text,
    char*           out_lang,
    float*          out_confidence
);

#ifdef __cplusplus
}
#endif

# Bella RAG System

Retrieval-Augmented Generation for the Bella persona (sweepstakes vertical).
At reply time, Bella retrieves the K most-similar historical customer→cashier
exchanges from `bella_rag_pairs` and feeds them to the LLM as "here's how
we've answered this before" examples.

## Architecture
- **Storage**: Postgres + pgvector, table `bella_rag_pairs`, 512-dim vectors
- **Embedder**: Voyage AI `voyage-3-lite` via `Bella::VoyageEmbedder`
- **Index**: HNSW + cosine distance
- **Industry-agnostic**: `industry` + `persona` columns scope retrieval per client

## One-time seeding
1. Place cleaned pairs at `/tmp/bella_training/pairs.jsonl` (see parser script)
2. Run: `bundle exec rake bella:seed_rag`
3. Test:  `bundle exec rake "bella:test_retrieval[load 20 to my juwa]"`

## Env
- `VOYAGE_API_KEY` (required, set in Railway env on both Chatwoot and SideKiq)

## Phase 3 (not yet wired)
`app/services/ai/reply_service.rb` will call `BellaRagPair.search_similar(...)` 
to augment the prompt with retrieved examples before calling Anthropic/Grok.

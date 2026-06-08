Diagnose the Patra RAG system state. Use the postgres MCP (or print psql commands for Genius if MCP unavailable). Check:
1. SELECT COUNT(*) FROM bella_rag_pairs;
2. SELECT COUNT(*) FROM bella_rag_pairs WHERE account_id IS NULL;
3. SELECT COUNT(DISTINCT real_intent) FROM bella_rag_pairs;
4. SELECT real_intent, COUNT(*) FROM bella_rag_pairs GROUP BY real_intent ORDER BY COUNT(*) DESC;
Report findings. Do NOT run any UPDATE or update_all — read only.

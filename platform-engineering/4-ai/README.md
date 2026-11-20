# Level 4: AI

These modules run AI workloads on Kubernetes. Modules 17 to 19 build on the [foundations](../1-foundations/README.md), mainly modules 3 to 6, and on module 12, while module 27 needs only module 0. Modules 17 and 19 need Ollama on your machine or a Claude API key, as [Choosing the model](../../docs/ai-models.md) explains. Module 27 needs Ollama for its search even when Claude writes the answers, and module 18 downloads about 900 MB of models into the cluster.

- [Module 17: An LLM as a mesh service](17-llm-in-the-mesh.md)
- [Module 18: Serving models in the cluster](18-serving-models.md)
- [Module 19: AI agents and their tools](19-ai-agents.md)
- [Module 27: RAG on Kubernetes](27-rag-on-kubernetes.md)

The [course overview](../README.md) shows the routes through all four levels and the recommended order.

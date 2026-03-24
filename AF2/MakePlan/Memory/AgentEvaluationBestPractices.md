# Agent Evaluation Best Practices

Based on learnings from Exa.ai's WebCode evaluation framework (2026-03-23).

## Core Principles

### 1. Separate Evaluation Dimensions

**Don't conflate different quality aspects:**
- Content extraction quality (how faithfully content is captured)
- Retrieval quality (whether relevant URLs are identified)
- Synthesis quality (how well the LLM generates responses)

**Why**: Conflating these makes it impossible to identify root causes of failures. A bad answer might be due to poor search results OR poor LLM reasoning.

### 2. Groundedness over Correctness

**Discriminative approach**: Ask the agent to highlight which passages contain the answer, rather than just generating an answer.

**Benefits**:
- Isolates search quality from LLM synthesis capabilities
- Reveals higher variance in retrieval differences
- Shows where agents are "hallucinating" vs. actually retrieving answers
- Correctness scores cluster similarly (~86%) but groundedness shows real differences

### 3. Test Against Post-Training Content

**Focus on information unavailable during model training:**
- Recent library releases (after August 2025)
- Breaking API changes
- New documentation
- Fresh GitHub issues

**Why**: Models can answer from parametric memory (training data) rather than actual retrieval. This contaminates benchmarks and doesn't test real-world search needs.

### 4. Multi-Dimensional Content Quality

**Seven metrics for content extraction:**
1. **Completeness**: How much substantive content is preserved (target >80%)
2. **Signal-to-Noise**: Ratio of useful content to boilerplate (aim for 5x-10x compression)
3. **Structure**: Preservation of headings, lists, hierarchy
4. **Accuracy**: Correctness against golden references
5. **Code Recall**: Percentage of code blocks extracted correctly (target >95%)
6. **Table Recall**: Percentage of tables preserved correctly
7. **ROUGE-L**: Text similarity scores

### 5. Golden Reference Generation

**Use multimodal approaches for reference creation:**
- Render pages in cloud browsers (headless)
- Capture screenshots
- Use vision models to produce faithful markdown
- Compare extractions against these golden standards

**Why**: Automated reference generation at scale, more faithful than manual annotation.

### 6. Content Optimization Strategies

**Extract only substantive content:**
- Strip navigation, ads, footers, sidebars
- Remove boilerplate and noise
- Preserve code blocks, tables, main content
- Maintain semantic structure

**Results**: 1x-13x leaner content significantly improves usefulness while preserving essential information.

### 7. End-to-End Task Validation

**Real coding tasks as evaluation:**
- Create tasks that require recent API knowledge
- Include verified solutions
- Provide test suites for validation
- Use Docker environments for reproducibility
- Ensure base models fail without search

**Why**: Tests real-world agent capabilities, not just retrieval metrics.

## Implementation Pattern

```
1. Content Quality Evaluator
   ├── Completeness scorer
   ├── Code/table recall metrics
   ├── Signal-to-noise analyzer
   └── ROUGE-L calculator

2. Groundedness Evaluator
   ├── Discriminative highlighting
   ├── Passage relevance scoring
   └── Separation from correctness

3. RAG Quality Tester
   ├── Authoritative source dataset
   ├── Post-training content focus
   └── Result set validation

4. Golden Reference Builder
   ├── Headless browser rendering
   ├── Screenshot capture
   ├── Multimodal markdown generation
   └── Reference storage

5. End-to-End Task Runner
   ├── Recent API task suite
   ├── Solution verification
   └── With/without search comparison
```

## Key Insights

- **Groundedness variance matters more than correctness clustering**: Correctness scores are similar across providers (~86%), but groundedness scores reveal actual retrieval quality differences.
- **Lean content wins**: 1x-13x compression with preserved semantics beats full-page extraction.
- **Contamination is real**: Public benchmarks saturate because models memorize training data. Always test post-training content.
- **Discriminative > Generative for eval**: Highlighting relevant passages isolates search quality better than answer generation.

## When to Apply

- Building or improving web search capabilities
- Evaluating RAG system quality
- Comparing search providers
- Measuring content extraction fidelity
- Diagnosing agent retrieval failures
- Optimizing context window usage (lean content)

## References

- Exa.ai WebCode blog post: https://exa.ai/blog/webcode
- Open-source benchmarks: github.com/exa-labs/benchmarks
- Session: 24a68e52-aa07-4de3-ad72-1184310b51ea
- Plan: 840-IvyAgent-NICETOHAVE-WebSearchEvaluationFramework.md

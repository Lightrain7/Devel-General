# DSPy Argumentative Text Extractor

A DSPy-based workflow for analyzing argumentative texts, extracting key components (topic sentence, evidence, analysis, tieback/transition), and detecting incomplete arguments. This project demonstrates how to use DSPy optimizers to create optimized prompts for rhetorical structure analysis.

## Features

- **Two-Stage Analysis**: First checks for completeness, then extracts components if complete
- **Flexible Training**: Supports both small and large datasets with different optimizers
- **Optimized Prompts**: Automatically generates effective few-shot prompts using DSPy
- **Runnable in Multiple Environments**: Works as a standalone script or in Jupyter notebooks

## Project Structure

```
.
├── argumentative_extractor.py    # Main Python script
├── DSPy_workflow.ipynb          # Jupyter notebook with full workflow
├── data.json                    # Small sample dataset (2 examples)
├── sample_large_dataset.json    # Larger sample dataset (10 examples)
├── data.txt                     # Raw text data for reference
├── optimized_extractor.json     # (Generated) Saved optimized model
├── README.md                    # This file
└── old.ipynb, old1.ipynb        # Legacy notebooks
```

## Installation

1. **Prerequisites**:
   - Python 3.8+
   - Google AI API key for Gemini model

2. **Install Dependencies**:
   ```bash
   pip install dspy-ai google-generativeai
   ```

3. **Set Up API Key**:
   - Edit `argumentative_extractor.py` and replace `"YOUR_API_KEY_HERE"` with your actual Gemini API key
   - Or set it as an environment variable: `export GOOGLE_API_KEY=your_key_here`

## Dataset Format

Training data must be in JSON format with the following structure:

```json
{
  "samples": [
    {
      "text": "Full argumentative text here...",
      "topic_sentence": "The main claim...",
      "evidence": "Supporting facts...",
      "analysis": "Explanation of evidence...",
      "tieback_or_transition": "Concluding statement..."
    },
    {
      "text": "Incomplete text here...",
      "missing": "evidence, analysis, tieback_or_transition"
    }
  ]
}
```

- **Complete samples**: Include all four components plus the full text
- **Incomplete samples**: Include only `"text"` and a comma-separated `"missing"` field
- Fields map directly to `dspy.Example` attributes

## Usage

### As a Standalone Script

Run from command line:
```bash
python argumentative_extractor.py sample_large_dataset.json
```

Optional arguments:
```bash
python argumentative_extractor.py data.json --optimizer BootstrapFewShot
```

- `--optimizer`: Choose `BootstrapFewShot` (small datasets) or `MIPROv2` (large datasets, default)

### In a Jupyter Notebook

```python
from argumentative_extractor import main

# Train and test the model
compiled_extractor = main('sample_large_dataset.json', 'MIPROv2')

# Use the trained model
result = compiled_extractor(text="Your text here...")
print(result)
```

## Understanding the Workflow

1. **Signatures**: Define input/output expectations for completeness checking and component extraction
2. **Module**: Combines two sub-modules that work sequentially
3. **Metric**: Evaluates extraction accuracy using exact string matching
4. **Optimization**: DSPy optimizer creates optimal prompts and few-shot examples
5. **Compilation**: Produces a ready-to-use model
6. **Testing**: Validates on unseen texts
7. **Prompt Inspection**: View the final human-readable prompts

## Optimizer Selection

- **BootstrapFewShot**: Good for small datasets (≤20 examples). Creates synthetic examples but can fail on large data due to API limits and token constraints.
- **MIPROv2**: Recommended for larger datasets. More efficient optimization with controlled complexity (`auto="light"`, `max_labeled_demos=3`).

### Why Large Datasets Fail with BootstrapFewShot

BootstrapFewShot generates new training examples by prompting the LM, leading to:
- High API usage and rate limits
- Token overflow (prompts exceed Gemini's limits)
- Long compilation times
- Potential overfitting on synthetic data

Use MIPROv2 for datasets >20 examples.

## Examples

### Complete Text Output
```
Topic Sentence: Regular physical activity leads to significant improvements in mental health.
Evidence: a 2023 study published in The Lancet showed that individuals who exercised...
Analysis: This outcome suggests that exercise acts as a powerful...
Tieback/Transition: Therefore, integrating exercise programs...
```

### Incomplete Text Output
```
Topic Sentence: None
Evidence: None
Analysis: None
Tieback/Transition: The provided text is incomplete. The following components are missing: evidence, analysis, tieback_or_transition.
```

## Advanced Usage

### Custom Metrics
Modify `is_text_complete_and_correct` for semantic similarity instead of exact matching:

```python
import dspy.evaluate
# Use semantic similarity
correct = dspy.evaluate.answer_semantic_similarity(prediction.topic_sentence, gold.topic_sentence) > 0.8
```

### Saving/Loading Models
```python
# Save compiled model
compiled_extractor.save('my_extractor.json')

# Load later
loaded_extractor = ArgumentativeExtractor()
loaded_extractor.load('my_extractor.json')
```

## Troubleshooting

- **API Errors**: Check your Gemini API key and quota limits
- **Compilation Failures**: For large datasets, use MIPROv2 and reduce `max_bootstrapped_demos`
- **Poor Performance**: Ensure training data quality and consider increasing demo counts
- **Memory Issues**: Process large datasets in batches or subset for training

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- Built with [DSPy](https://dspy.ai/) framework
- Uses Google's Gemini for language model capabilities
- Inspired by rhetorical structure theory for argumentative analysis
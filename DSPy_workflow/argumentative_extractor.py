import dspy
import json
import argparse

# Configure the language model (adjust API key and model as needed)
lm = dspy.LM(model="gemini/gemini-flash-latest", api_key="YOUR_API_KEY_HERE")
dspy.configure(lm=lm)

# Define signatures
class TextCompleteness(dspy.Signature):
    text = dspy.InputField(desc="Text to analyze for completeness.")
    missing_components = dspy.OutputField(
        desc="A comma-separated list of missing components from the set: 'topic_sentence', 'evidence', 'analysis', 'tieback_or_transition'. If all components are present, respond with 'all_present'."
    )

class ArgumentativeStructure(dspy.Signature):
    context = dspy.InputField(desc="A passage of text to be analyzed.")
    topic_sentence = dspy.OutputField(desc="The main point or topic sentence of the text.")
    evidence = dspy.OutputField(desc="Specific facts, data, or examples from the text that support the topic sentence.")
    analysis = dspy.OutputField(desc="An explanation of how the evidence supports the topic sentence.")
    tieback_or_transition = dspy.OutputField(desc="A sentence that connects the analysis back to the main argument or transitions to the next idea.")

# Define the module
class ArgumentativeExtractor(dspy.Module):
    def __init__(self):
        super().__init__()
        self.completeness_classifier = dspy.Predict(TextCompleteness)
        self.structure_extractor = dspy.Predict(ArgumentativeStructure)

    def forward(self, text):
        completeness_result = self.completeness_classifier(text=text)
        if "all_present" in completeness_result.missing_components.lower():
            extraction_result = self.structure_extractor(context=text)
            return extraction_result
        else:
            missing_parts = completeness_result.missing_components.replace(" ", "").split(",")
            message = f"The provided text is incomplete. The following components are missing: {', '.join(missing_parts)}."
            return dspy.Prediction(
                topic_sentence=None,
                evidence=None,
                analysis=None,
                tieback_or_transition=message
            )

# Metric function
def is_text_complete_and_correct(example, prediction):
    if "missing" in example:
        expected_missing_parts = sorted(example["missing"].split(','))
        predicted_missing_parts = sorted(prediction.tieback_or_transition.split(':')[-1].strip().split(', '))
        if all(part in predicted_missing_parts for part in expected_missing_parts):
            print("✔️ Correctly identified missing components.")
            return True
        else:
            print(f"❌ Incorrectly identified missing components. Expected: {expected_missing_parts}, Got: {predicted_missing_parts}")
            return False
    else:
        correct = all(
            dspy.evaluate.answer_exact_match(prediction.topic_sentence, example["topic_sentence"]),
            dspy.evaluate.answer_exact_match(prediction.evidence, example["evidence"]),
            dspy.evaluate.answer_exact_match(prediction.analysis, example["analysis"]),
            dspy.evaluate.answer_exact_match(prediction.tieback_or_transition, example["tieback_or_transition"])
        )
        if correct:
            print("✔️ All components were correctly extracted.")
        else:
            print("❌ One or more components were incorrectly extracted.")
        return correct

# Function to load training data from JSON
def load_trainset(json_file_path):
    with open(json_file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    trainset = []
    for sample in data["samples"]:
        example = dspy.Example(**sample)
        trainset.append(example)
    return trainset

def main(json_file_path, optimizer_type="MIPROv2"):
    """
    Main function to train and test the ArgumentativeExtractor.

    Args:
        json_file_path (str): Path to the JSON file containing the training data.
        optimizer_type (str): "BootstrapFewShot" or "MIPROv2" (default).
    """
    # Load training data
    trainset = load_trainset(json_file_path)

    # Initialize optimizer
    if optimizer_type == "BootstrapFewShot":
        optimizer = dspy.BootstrapFewShot(metric=is_text_complete_and_correct)
    else:  # MIPROv2
        optimizer = dspy.teleprompt.MIPROv2(
            prompt_model=lm,
            metric=is_text_complete_and_correct,
            auto="light",
            max_labeled_demos=3,
            max_bootstrapped_demos=3
        )

    # Compile the module
    print("Compiling the module...")
    compiled_extractor = optimizer.compile(student=ArgumentativeExtractor(), trainset=trainset)
    print("Compilation complete.")

    # Test on sample texts
    unseen_text_complete = "Regular physical activity leads to significant improvements in mental health. For instance, a 2023 study published in The Lancet showed that individuals who exercised for at least 150 minutes per week reported a 30% reduction in symptoms of anxiety and depression compared to a control group. This outcome suggests that exercise acts as a powerful non-pharmacological intervention, directly impacting neurological pathways related to mood regulation. Therefore, integrating exercise programs into public health initiatives is an effective way to address the growing mental health crisis."

    unseen_text_incomplete = "Dogs are the best pets."

    print(f"\nOriginal Text: {unseen_text_complete}")
    print(f"Compiled Output:\n{compiled_extractor(text=unseen_text_complete)}")

    print("\n" + "="*50)

    print(f"Original Text: {unseen_text_incomplete}")
    print(f"Compiled Output:\n{compiled_extractor(text=unseen_text_incomplete)}")

    # Print the full prompt
    print_full_prompt(compiled_extractor)

    return compiled_extractor

def print_full_prompt(compiled_module):
    print("\n=== FULL COMPLETENESS CLASSIFIER PROMPT ===")
    print("Instructions:")
    print(compiled_module.completeness_classifier.signature.instructions)
    print("\nFew-shot Examples:")
    for i, demo in enumerate(compiled_module.completeness_classifier.demos or [], 1):
        print(f"Example {i}:")
        print(f"Text: {demo.text}")
        print(f"Missing Components: {demo.missing_components}")
        print()

    print("=== FULL STRUCTURE EXTRACTOR PROMPT ===")
    print("Instructions:")
    print(compiled_module.structure_extractor.signature.instructions)
    print("\nFew-shot Examples:")
    for i, demo in enumerate(compiled_module.structure_extractor.demos or [], 1):
        print(f"Example {i}:")
        print(f"Context: {demo.context}")
        print(f"Topic Sentence: {demo.topic_sentence}")
        print(f"Evidence: {demo.evidence}")
        print(f"Analysis: {demo.analysis}")
        print(f"Tieback/Transition: {demo.tieback_or_transition}")
        print()

# Main script for command-line usage
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train and test an ArgumentativeExtractor using DSPy.")
    parser.add_argument("json_file", help="Path to the JSON file containing the training data.")
    parser.add_argument("--optimizer", choices=["BootstrapFewShot", "MIPROv2"], default="MIPROv2", help="Optimizer to use (default: MIPROv2 for larger datasets).")
    args = parser.parse_args()

    main(args.json_file, args.optimizer)
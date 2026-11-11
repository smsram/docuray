import sys
try:
    import tflite_runtime.interpreter as tflite
    Interpreter = tflite.Interpreter
except ImportError:
    try:
        import tensorflow as tf
        Interpreter = tf.lite.Interpreter
    except ImportError:
        print("Neither tflite_runtime nor tensorflow installed. Checking available modules...")
        import importlib
        sys.exit(1)

interpreter = Interpreter(model_path='assets/models/paper_corner_detector.tflite')
interpreter.allocate_tensors()
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

print('=== INPUT DETAILS ===')
for i, inp in enumerate(input_details):
    print(f"Input {i}: name={inp['name']}, shape={inp['shape']}, dtype={inp['dtype']}, quant={inp['quantization']}")

print('=== OUTPUT DETAILS ===')
for i, out in enumerate(output_details):
    print(f"Output {i}: name={out['name']}, shape={out['shape']}, dtype={out['dtype']}, quant={out['quantization']}")

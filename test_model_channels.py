import numpy as np
import tensorflow as tf

interpreter = tf.lite.Interpreter(model_path='assets/models/paper_corner_detector.tflite')
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

print("Input details:", input_details[0])
print("Output details:", output_details[0])

# Test with a dummy image (zeros, ones, random)
dummy_zeros = np.zeros((1, 640, 640, 3), dtype=np.float32)
interpreter.set_tensor(input_details[0]['index'], dummy_zeros)
interpreter.invoke()
out_zeros = interpreter.get_tensor(output_details[0]['index'])

print("Output shape:", out_zeros.shape)
print("Output min/max for zeros:")
for c in range(17):
    print(f"Channel {c}: min={out_zeros[0, c, :].min():.4f}, max={out_zeros[0, c, :].max():.4f}, mean={out_zeros[0, c, :].mean():.4f}")

# Test with a sample document image if available
import glob
images = glob.glob('assets/**/*.png', recursive=True) + glob.glob('assets/**/*.jpg', recursive=True)
print("Available images:", images)

if images:
    from PIL import Image
    im = Image.open(images[0]).convert('RGB').resize((640, 640))
    arr = np.array(im, dtype=np.float32) / 255.0
    arr = np.expand_dims(arr, axis=0)
    interpreter.set_tensor(input_details[0]['index'], arr)
    interpreter.invoke()
    out = interpreter.get_tensor(output_details[0]['index'])
    print(f"\nInference on {images[0]}:")
    for c in range(17):
        print(f"Channel {c}: min={out[0, c, :].min():.4f}, max={out[0, c, :].max():.4f}, mean={out[0, c, :].mean():.4f}")
    
    # Find highest score in channel 4
    scores = out[0, 4, :]
    top_indices = np.argsort(scores)[::-1][:5]
    print(f"Top 5 scores in ch 4: {scores[top_indices]}")
    for idx in top_indices[:3]:
        print(f"Anchor {idx}: box=[{out[0, 0, idx]:.1f}, {out[0, 1, idx]:.1f}, {out[0, 2, idx]:.1f}, {out[0, 3, idx]:.1f}], score={scores[idx]:.3f}")
        for kp in range(4):
            # keypoints are channels 5..16: (5,6,7), (8,9,10), (11,12,13), (14,15,16)
            kpx = out[0, 5 + kp*3, idx]
            kpy = out[0, 5 + kp*3 + 1, idx]
            kpc = out[0, 5 + kp*3 + 2, idx]
            print(f"  KP {kp}: x={kpx:.2f}, y={kpy:.2f}, conf={kpc:.3f}")

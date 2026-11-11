# Document Paper Corner Detector Model Specification

**Active Model File**: `assets/models/best.tflite`  
**Size**: 13,797,758 bytes (~13.8 MB)  
**Format**: TensorFlow Lite (TFL3 flatbuffer with embedded Ultralytics metadata)  
**Model Architecture**: Ultralytics YOLOv8n-seg (Instance Segmentation Document Detector)  
**Trained Class**: `0: document`  
**Trained Image Size**: `640 x 640`  
**Embedded Version**: Ultralytics 8.4.207  

---

## 1. Input Tensor Details

| Property | Value | Notes |
| :--- | :--- | :--- |
| **Count** | 1 | Single input tensor |
| **Index** | 0 | Input tensor index |
| **Name** | `serving_default_args_0` | RGB input image frame |
| **Shape** | `[1, 3, 640, 640]` | **NCHW (Channels-First)**: Batch: 1, Channels: 3, Height: 640, Width: 640 |
| **Data Type** | `Float32` | Standard 32-bit floating point |
| **Normalization** | `[0.0, 1.0]` | Pixel values normalized by dividing RGB by `255.0` |
| **Color Order** | **RGB** | Channel 0: Red, Channel 1: Green, Channel 2: Blue |

> [!IMPORTANT]
> The model uses **NCHW (Channels-First)** format: `[1, 3, 640, 640]`. In the input buffer, all Red channel pixels $(640 \times 640)$ are contiguous, followed by all Green channel pixels $(640 \times 640)$, followed by all Blue channel pixels $(640 \times 640)$.

---

## 2. Output Tensor Details

The model produces **two distinct output tensors**:

| Output | Name | Shape | Data Type | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Output 0** | `serving_default_output_0_output` | `[1, 37, 8400]` | `Float32` | Box coordinates, document score, and 32 mask coefficients across 8,400 anchors |
| **Output 1** | `serving_default_output_1_output` | `[1, 32, 160, 160]` | `Float32` | 32 mask prototypes at $160 \times 160$ spatial resolution |

---

## 3. Output 0 Vector Layout (37 Channels)

For each anchor index $i \in [0, 8399]$:

| Channel Index | Attribute | Range | Description |
| :---: | :--- | :---: | :--- |
| **0** | `cx` | `[0.0, 1.0]` | Center X of document bounding box (normalized) |
| **1** | `cy` | `[0.0, 1.0]` | Center Y of document bounding box (normalized) |
| **2** | `w` | `[0.0, 1.0]` | Width of document bounding box (normalized) |
| **3** | `h` | `[0.0, 1.0]` | Height of document bounding box (normalized) |
| **4** | `score` | `[0.0, 1.0]` | Document object classification confidence score |
| **5 .. 36** | `weights[0..31]` | `[-3.0, 3.0]` | 32 linear mask prototype coefficients |

---

## 4. Segmentation Mask & 4-Corner Reconstruction Pipeline

1. **Best Detection Selection**:
   - Locate the anchor $i^* = \arg\max_{i} (\text{score}_i)$.
   - Reject prediction if $\text{score}_{i^*} < 0.40$ (minimum confidence threshold).

2. **Prototype Mask Combination**:
   - Compute the raw spatial mask $\mathcal{M}$ on the $160 \times 160$ prototype grid:
     $$\mathcal{M}(x, y) = \sum_{k=0}^{31} \text{weights}[k] \cdot \text{proto}[k][y][x]$$
   - Binary document segmentation condition: $\mathcal{M}(x, y) > 0$ (equivalent to $\sigma(\mathcal{M}) > 0.5$).
   - Bound evaluation to the bounding box $[cx - w/2 - \delta, cx + w/2 + \delta] \times [cy - h/2 - \delta, cy + h/2 + \delta]$ on the $160 \times 160$ grid.

3. **Geometric Corner Extraction**:
   - Extract boundary contour pixels from the positive mask region.
   - Compute the convex hull using Andrew's Monotone Chain algorithm.
   - Simplify the convex polygon using Douglas-Peucker to identify the 4 principal vertices.
   - Normalize coordinates from $160 \times 160$ to $[0.0, 1.0]$: $(x/160.0, y/160.0)$.

4. **Corner Sorting & Quadrilateral Validation**:
   - Consistently arrange points in clockwise order:
     - **Top-Left (0)**
     - **Top-Right (1)**
     - **Bottom-Right (2)**
     - **Bottom-Left (3)**
   - Check strict convexity using consecutive edge cross products ($(\vec{AB} \times \vec{BC}) > 0$).
   - Check minimum area threshold (Shoelace formula $\ge 0.08$).

5. **Temporal Stabilization**:
   - Apply Exponential Moving Average (EMA) with $\alpha = 0.35$ across consecutive valid frames to eliminate hand jitter.

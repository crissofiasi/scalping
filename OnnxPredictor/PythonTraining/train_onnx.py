"""
XAUUSD ONNX Model Training Script
Trains neural network and exports to ONNX format for MT5
"""

import os
import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers, models, callbacks
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime

# Try importing ONNX libraries
try:
    import tf2onnx
    import onnx
    ONNX_AVAILABLE = True
except ImportError:
    print("WARNING: ONNX libraries not available. Install with: pip install tf2onnx onnx")
    ONNX_AVAILABLE = False

class Config:
    """Training configuration"""
    # Paths
    DATA_FILE = "XAUUSD_training_data.csv"
    MODEL_H5 = "xauusd_model.h5"
    MODEL_ONNX = "../Models/xauusd_model.onnx"
    SCALER_FILE = "feature_scaler.npy"
    
    # Training params
    TEST_SIZE = 0.20
    VALIDATION_SIZE = 0.20
    BATCH_SIZE = 64
    EPOCHS = 200
    LEARNING_RATE = 0.001
    RANDOM_STATE = 42
    
    # Model architecture
    DROPOUT_RATE = 0.3
    L2_REG = 0.0001
    
    # Early stopping
    PATIENCE = 30
    MIN_DELTA = 0.0001

def load_data(filepath):
    """Load and prepare data"""
    print(f"\n{'='*60}")
    print("LOADING DATA")
    print(f"{'='*60}")
    
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Data file not found: {filepath}")
    
    # Read CSV
    df = pd.read_csv(filepath)
    print(f"Loaded {len(df)} samples")
    print(f"Columns: {len(df.columns)}")
    
    # Remove invalid labels
    initial_count = len(df)
    valid_labels = (df.iloc[:, -1] == 1.0) | (df.iloc[:, -1] == 0.0)
    df = df[valid_labels]
    df = df.dropna()
    
    removed = initial_count - len(df)
    if removed > 0:
        print(f"Removed {removed} invalid/NaN samples")
    
    # Separate features and labels
    X = df.iloc[:, :-1].values
    y = df.iloc[:, -1].values
    
    print(f"\nFinal dataset:")
    print(f"  Samples: {len(X)}")
    print(f"  Features: {X.shape[1]}")
    print(f"  BUY signals: {np.sum(y == 1.0)} ({np.sum(y == 1.0)/len(y)*100:.1f}%)")
    print(f"  SELL signals: {np.sum(y == 0.0)} ({np.sum(y == 0.0)/len(y)*100:.1f}%)")
    
    return X, y

def create_model(input_dim, learning_rate=0.001):
    """
    Create enhanced neural network for XAUUSD prediction
    Architecture optimized for many features and MTF analysis
    """
    print(f"\n{'='*60}")
    print("BUILDING MODEL")
    print(f"{'='*60}")
    
    # Calculate layer sizes based on input
    layer1 = min(input_dim * 2, 1024)
    layer2 = min(input_dim, 512)
    layer3 = max(input_dim // 2, 128)
    layer4 = max(input_dim // 4, 64)
    
    print(f"Architecture: {input_dim} → [{layer1}, {layer2}, {layer3}, {layer4}] → 1")
    
    model = keras.Sequential([
        # Input layer
        layers.Input(shape=(input_dim,), name='input'),
        
        # Layer 1
        layers.Dense(layer1, kernel_regularizer=keras.regularizers.l2(Config.L2_REG), name='dense1'),
        layers.BatchNormalization(name='bn1'),
        layers.Activation('swish', name='act1'),
        layers.Dropout(Config.DROPOUT_RATE, name='dropout1'),
        
        # Layer 2
        layers.Dense(layer2, kernel_regularizer=keras.regularizers.l2(Config.L2_REG), name='dense2'),
        layers.BatchNormalization(name='bn2'),
        layers.Activation('swish', name='act2'),
        layers.Dropout(Config.DROPOUT_RATE, name='dropout2'),
        
        # Layer 3
        layers.Dense(layer3, kernel_regularizer=keras.regularizers.l2(Config.L2_REG), name='dense3'),
        layers.BatchNormalization(name='bn3'),
        layers.Activation('swish', name='act3'),
        layers.Dropout(Config.DROPOUT_RATE * 0.7, name='dropout3'),
        
        # Layer 4
        layers.Dense(layer4, kernel_regularizer=keras.regularizers.l2(Config.L2_REG), name='dense4'),
        layers.BatchNormalization(name='bn4'),
        layers.Activation('swish', name='act4'),
        layers.Dropout(Config.DROPOUT_RATE * 0.5, name='dropout4'),
        
        # Output
        layers.Dense(1, activation='sigmoid', name='output')
    ], name='XAUUSD_Predictor')
    
    # Compile
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=learning_rate),
        loss='binary_crossentropy',
        metrics=[
            'accuracy',
            keras.metrics.Precision(name='precision'),
            keras.metrics.Recall(name='recall')
        ]
    )
    
    model.summary()
    return model

def train_model(model, X_train, y_train, X_val, y_val):
    """Train the model"""
    print(f"\n{'='*60}")
    print("TRAINING MODEL")
    print(f"{'='*60}")
    
    # Callbacks
    early_stop = callbacks.EarlyStopping(
        monitor='val_loss',
        patience=Config.PATIENCE,
        restore_best_weights=True,
        verbose=1
    )
    
    reduce_lr = callbacks.ReduceLROnPlateau(
        monitor='val_loss',
        factor=0.5,
        patience=10,
        min_lr=1e-7,
        verbose=1
    )
    
    checkpoint = callbacks.ModelCheckpoint(
        'best_model.h5',
        monitor='val_accuracy',
        save_best_only=True,
        verbose=1
    )
    
    # Train
    history = model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=Config.EPOCHS,
        batch_size=Config.BATCH_SIZE,
        callbacks=[early_stop, reduce_lr, checkpoint],
        verbose=1
    )
    
    return history

def evaluate_model(model, X_test, y_test):
    """Evaluate model performance"""
    print(f"\n{'='*60}")
    print("MODEL EVALUATION")
    print(f"{'='*60}")
    
    # Predictions
    y_pred_prob = model.predict(X_test, verbose=0)
    y_pred = (y_pred_prob > 0.5).astype(int).flatten()
    
    # Metrics
    from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, confusion_matrix
    
    accuracy = accuracy_score(y_test, y_pred)
    precision = precision_score(y_test, y_pred)
    recall = recall_score(y_test, y_pred)
    f1 = f1_score(y_test, y_pred)
    cm = confusion_matrix(y_test, y_pred)
    
    print(f"\nTest Set Performance:")
    print(f"  Accuracy:  {accuracy*100:.2f}%")
    print(f"  Precision: {precision*100:.2f}%")
    print(f"  Recall:    {recall*100:.2f}%")
    print(f"  F1-Score:  {f1*100:.2f}%")
    
    print(f"\nConfusion Matrix:")
    print(f"  TN: {cm[0][0]:5d}  FP: {cm[0][1]:5d}")
    print(f"  FN: {cm[1][0]:5d}  TP: {cm[1][1]:5d}")
    
    # Confidence analysis
    print(f"\nConfidence Analysis:")
    for threshold in [0.55, 0.60, 0.65, 0.70, 0.75, 0.80]:
        mask = (y_pred_prob.flatten() > threshold) | (y_pred_prob.flatten() < (1 - threshold))
        if np.sum(mask) > 0:
            conf_accuracy = accuracy_score(y_test[mask], y_pred[mask])
            coverage = np.sum(mask) / len(mask) * 100
            print(f"  Confidence >{threshold:.2f}: {conf_accuracy*100:.2f}% accuracy ({coverage:.1f}% of signals)")
    
    return {
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'f1': f1,
        'confusion_matrix': cm,
        'predictions': y_pred,
        'probabilities': y_pred_prob
    }

def export_to_onnx(model, input_shape, output_path):
    """Export model to ONNX format"""
    print(f"\n{'='*60}")
    print("EXPORTING TO ONNX")
    print(f"{'='*60}")
    
    if not ONNX_AVAILABLE:
        print("ERROR: ONNX libraries not available")
        print("Install with: pip install tf2onnx onnx")
        return False
    
    try:
        # Create dummy input
        dummy_input = tf.constant(np.random.randn(1, input_shape).astype(np.float32))
        
        # Convert to ONNX
        model_proto, _ = tf2onnx.convert.from_keras(
            model,
            input_signature=[tf.TensorSpec(shape=(None, input_shape), dtype=tf.float32, name='input')],
            opset=13
        )
        
        # Save
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        onnx.save(model_proto, output_path)
        
        # Verify
        onnx_model = onnx.load(output_path)
        onnx.checker.check_model(onnx_model)
        
        file_size = os.path.getsize(output_path) / (1024 * 1024)
        print(f"✅ ONNX model exported: {output_path}")
        print(f"   Size: {file_size:.2f} MB")
        print(f"   Input shape: (None, {input_shape})")
        print(f"   Output shape: (None, 1)")
        
        return True
        
    except Exception as e:
        print(f"ERROR exporting to ONNX: {str(e)}")
        return False

def plot_training_history(history):
    """Plot training curves"""
    fig, axes = plt.subplots(2, 2, figsize=(15, 10))
    
    # Accuracy
    axes[0, 0].plot(history.history['accuracy'], label='Train')
    axes[0, 0].plot(history.history['val_accuracy'], label='Validation')
    axes[0, 0].set_title('Model Accuracy')
    axes[0, 0].set_xlabel('Epoch')
    axes[0, 0].set_ylabel('Accuracy')
    axes[0, 0].legend()
    axes[0, 0].grid(True)
    
    # Loss
    axes[0, 1].plot(history.history['loss'], label='Train')
    axes[0, 1].plot(history.history['val_loss'], label='Validation')
    axes[0, 1].set_title('Model Loss')
    axes[0, 1].set_xlabel('Epoch')
    axes[0, 1].set_ylabel('Loss')
    axes[0, 1].legend()
    axes[0, 1].grid(True)
    
    # Precision
    axes[1, 0].plot(history.history['precision'], label='Train')
    axes[1, 0].plot(history.history['val_precision'], label='Validation')
    axes[1, 0].set_title('Precision')
    axes[1, 0].set_xlabel('Epoch')
    axes[1, 0].set_ylabel('Precision')
    axes[1, 0].legend()
    axes[1, 0].grid(True)
    
    # Recall
    axes[1, 1].plot(history.history['recall'], label='Train')
    axes[1, 1].plot(history.history['val_recall'], label='Validation')
    axes[1, 1].set_title('Recall')
    axes[1, 1].set_xlabel('Epoch')
    axes[1, 1].set_ylabel('Recall')
    axes[1, 1].legend()
    axes[1, 1].grid(True)
    
    plt.tight_layout()
    plt.savefig('training_history.png', dpi=150)
    print(f"✅ Saved training history: training_history.png")

def main():
    """Main training pipeline"""
    print("="*60)
    print("XAUUSD ONNX MODEL TRAINING")
    print("="*60)
    print(f"TensorFlow version: {tf.__version__}")
    print(f"ONNX export available: {ONNX_AVAILABLE}")
    
    # GPU check
    gpus = tf.config.list_physical_devices('GPU')
    if gpus:
        print(f"✅ GPU available: {len(gpus)} device(s)")
    else:
        print("⚠️  No GPU detected, using CPU")
    
    # Load data
    X, y = load_data(Config.DATA_FILE)
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=Config.TEST_SIZE, random_state=Config.RANDOM_STATE, stratify=y
    )
    
    X_train, X_val, y_train, y_val = train_test_split(
        X_train, y_train, test_size=Config.VALIDATION_SIZE, random_state=Config.RANDOM_STATE, stratify=y_train
    )
    
    print(f"\nDataset split:")
    print(f"  Training:   {len(X_train)} samples")
    print(f"  Validation: {len(X_val)} samples")
    print(f"  Test:       {len(X_test)} samples")
    
    # Feature scaling (optional, but can help)
    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train)
    X_val = scaler.transform(X_val)
    X_test = scaler.transform(X_test)
    
    # Save scaler
    np.save(Config.SCALER_FILE, {
        'mean': scaler.mean_,
        'scale': scaler.scale_
    })
    print(f"✅ Saved feature scaler: {Config.SCALER_FILE}")
    
    # Create model
    model = create_model(X_train.shape[1], Config.LEARNING_RATE)
    
    # Train
    history = train_model(model, X_train, y_train, X_val, y_val)
    
    # Evaluate
    results = evaluate_model(model, X_test, y_test)
    
    # Save H5 model
    model.save(Config.MODEL_H5)
    print(f"\n✅ Saved Keras model: {Config.MODEL_H5}")
    
    # Export to ONNX
    if export_to_onnx(model, X_train.shape[1], Config.MODEL_ONNX):
        print(f"\n{'='*60}")
        print("✅ ONNX EXPORT SUCCESSFUL")
        print(f"{'='*60}")
        print(f"\nNext steps:")
        print(f"1. Copy {Config.MODEL_ONNX} to MT5 Common Files folder")
        print(f"2. Copy {Config.SCALER_FILE} to MT5 Common Files folder")
        print(f"3. Run the XAUUSD ONNX EA on MT5")
    else:
        print("\n⚠️  ONNX export failed, but Keras model saved")
    
    # Plot history
    plot_training_history(history)
    
    print(f"\n{'='*60}")
    print("TRAINING COMPLETE")
    print(f"{'='*60}")

if __name__ == "__main__":
    main()

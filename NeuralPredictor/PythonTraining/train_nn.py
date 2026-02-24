"""
Neural Network Training Script for MT5 Predictor
Trains a neural network on exported MT5 data using TensorFlow/Keras
Much faster than MQL5 training (10-100x speedup with GPU)
"""

import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers, optimizers
from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau, ModelCheckpoint
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, precision_score, recall_score, confusion_matrix
import matplotlib.pyplot as plt
import seaborn as sns
import json
import os
from datetime import datetime

# Configuration
class Config:
    """Training configuration"""
    # Data settings
    DATA_FILE = "nn_training_data.csv"
    TEST_SIZE = 0.2
    RANDOM_STATE = 42
    
    # Network architecture (adjust based on single/multi TF)
    SINGLE_TF_ARCH = [50, 30, 15]  # 25 inputs
    MULTI_TF_ARCH = [80, 50, 30]   # 75 inputs
    
    # Training settings
    EPOCHS = 1000
    BATCH_SIZE = 64
    LEARNING_RATE = 0.001
    EARLY_STOPPING_PATIENCE = 50
    REDUCE_LR_PATIENCE = 20
    
    # Regularization
    DROPOUT_RATE = 0.3
    L2_REG = 0.0001
    
    # Output settings
    MODEL_OUTPUT = "trained_model.h5"
    WEIGHTS_JSON = "model_weights.json"
    HISTORY_PLOT = "training_history.png"
    CONFUSION_MATRIX_PLOT = "confusion_matrix.png"
    EVALUATION_REPORT = "evaluation_report.txt"

def load_data(filepath):
    """Load and prepare training data"""
    print(f"Loading data from {filepath}...")
    
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Data file not found: {filepath}")
    
    # Try UTF-16 encoding first (MT5 default), fallback to UTF-8
    try:
        df = pd.read_csv(filepath, encoding='utf-16')
    except UnicodeDecodeError:
        df = pd.read_csv(filepath, encoding='utf-8')
    
    print(f"Loaded {len(df)} samples")
    
    # Clean data - remove invalid labels
    initial_count = len(df)
    valid_labels = (df.iloc[:, -1] == 1.0) | (df.iloc[:, -1] == 0.0)
    df = df[valid_labels]
    
    # Remove any rows with NaN values
    df = df.dropna()
    
    removed_count = initial_count - len(df)
    if removed_count > 0:
        print(f"Removed {removed_count} invalid samples")
    
    # Separate features and labels
    X = df.iloc[:, :-1].values  # All columns except last
    y = df.iloc[:, -1].values    # Last column (Label)
    
    print(f"Feature shape: {X.shape}")
    print(f"Label distribution - BUY: {np.sum(y == 1.0)}, SELL: {np.sum(y == 0.0)}")
    
    return X, y

def create_model(input_dim, architecture, dropout_rate=0.3, l2_reg=0.0001):
    """
    Create neural network model
    
    Args:
        input_dim: Number of input features (25 for single TF, 75 for multi TF)
        architecture: List of hidden layer sizes [layer1, layer2, layer3]
        dropout_rate: Dropout probability for regularization
        l2_reg: L2 regularization strength
    
    Returns:
        Compiled Keras model
    """
    print(f"\nBuilding model architecture: {input_dim} -> {architecture} -> 1")
    
    model = keras.Sequential(name="NeuralPredictor")
    
    # Input layer
    model.add(layers.Input(shape=(input_dim,), name="input_layer"))
    
    # Hidden layers with batch normalization and dropout
    for i, units in enumerate(architecture):
        if units > 0:  # Skip if 0 (for compatibility with 2-layer networks)
            model.add(layers.Dense(
                units,
                activation='swish',  # Swish activation (same as MQL5)
                kernel_regularizer=keras.regularizers.l2(l2_reg),
                name=f"hidden_layer_{i+1}"
            ))
            model.add(layers.BatchNormalization(name=f"batch_norm_{i+1}"))
            model.add(layers.Dropout(dropout_rate, name=f"dropout_{i+1}"))
    
    # Output layer
    model.add(layers.Dense(1, activation='sigmoid', name="output_layer"))
    
    # Compile model
    model.compile(
        optimizer=optimizers.Adam(learning_rate=Config.LEARNING_RATE),
        loss='binary_crossentropy',
        metrics=['accuracy', keras.metrics.Precision(), keras.metrics.Recall()]
    )
    
    model.summary()
    return model

def train_model(model, X_train, y_train, X_val, y_val):
    """Train the model with callbacks"""
    print("\nStarting training...")
    print(f"Training samples: {len(X_train)}")
    print(f"Validation samples: {len(X_val)}")
    
    # Callbacks
    callbacks = [
        EarlyStopping(
            monitor='val_loss',
            patience=Config.EARLY_STOPPING_PATIENCE,
            restore_best_weights=True,
            verbose=1
        ),
        ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=Config.REDUCE_LR_PATIENCE,
            min_lr=1e-7,
            verbose=1
        ),
        ModelCheckpoint(
            'best_model_checkpoint.h5',
            monitor='val_accuracy',
            save_best_only=True,
            verbose=1
        )
    ]
    
    # Train
    start_time = datetime.now()
    
    history = model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=Config.EPOCHS,
        batch_size=Config.BATCH_SIZE,
        callbacks=callbacks,
        verbose=1
    )
    
    training_time = (datetime.now() - start_time).total_seconds()
    print(f"\nTraining completed in {training_time:.2f} seconds ({training_time/60:.2f} minutes)")
    
    return history

def evaluate_model(model, X_test, y_test):
    """Evaluate model performance"""
    print("\n" + "="*50)
    print("MODEL EVALUATION")
    print("="*50)
    
    # Predictions
    y_pred_prob = model.predict(X_test, verbose=0)
    y_pred = (y_pred_prob > 0.5).astype(int).flatten()
    y_test = y_test.astype(int)
    
    # Metrics
    accuracy = accuracy_score(y_test, y_pred)
    precision = precision_score(y_test, y_pred, zero_division=0)
    recall = recall_score(y_test, y_pred, zero_division=0)
    
    print(f"\nTest Set Performance:")
    print(f"  Accuracy:  {accuracy*100:.2f}%")
    print(f"  Precision: {precision*100:.2f}%")
    print(f"  Recall:    {recall*100:.2f}%")
    
    # Confusion matrix
    cm = confusion_matrix(y_test, y_pred)
    print(f"\nConfusion Matrix:")
    print(f"  True Negatives (SELL):  {cm[0,0]}")
    print(f"  False Positives:        {cm[0,1]}")
    print(f"  False Negatives:        {cm[1,0]}")
    print(f"  True Positives (BUY):   {cm[1,1]}")
    
    # Confidence analysis
    print(f"\nConfidence Analysis:")
    for threshold in [0.6, 0.65, 0.7, 0.75, 0.8]:
        confident_mask = (y_pred_prob < (1-threshold)) | (y_pred_prob > threshold)
        confident_mask = confident_mask.flatten()
        
        if np.sum(confident_mask) > 0:
            conf_y_test = y_test[confident_mask]
            conf_y_pred = y_pred[confident_mask]
            conf_acc = accuracy_score(conf_y_test, conf_y_pred)
            conf_pct = np.sum(confident_mask) / len(y_test) * 100
            print(f"  Confidence >{threshold:.2f}: {conf_acc*100:.2f}% accuracy ({conf_pct:.1f}% of signals)")
    
    return {
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'confusion_matrix': cm.tolist(),
        'predictions': y_pred_prob.flatten().tolist()
    }

def plot_training_history(history):
    """Plot training history"""
    print(f"\nGenerating training history plot...")
    
    fig, axes = plt.subplots(2, 2, figsize=(15, 10))
    fig.suptitle('Training History', fontsize=16)
    
    # Loss
    axes[0, 0].plot(history.history['loss'], label='Train Loss')
    axes[0, 0].plot(history.history['val_loss'], label='Val Loss')
    axes[0, 0].set_title('Model Loss')
    axes[0, 0].set_xlabel('Epoch')
    axes[0, 0].set_ylabel('Loss')
    axes[0, 0].legend()
    axes[0, 0].grid(True)
    
    # Accuracy
    axes[0, 1].plot(history.history['accuracy'], label='Train Acc')
    axes[0, 1].plot(history.history['val_accuracy'], label='Val Acc')
    axes[0, 1].set_title('Model Accuracy')
    axes[0, 1].set_xlabel('Epoch')
    axes[0, 1].set_ylabel('Accuracy')
    axes[0, 1].legend()
    axes[0, 1].grid(True)
    
    # Precision
    axes[1, 0].plot(history.history['precision'], label='Train Precision')
    axes[1, 0].plot(history.history['val_precision'], label='Val Precision')
    axes[1, 0].set_title('Model Precision')
    axes[1, 0].set_xlabel('Epoch')
    axes[1, 0].set_ylabel('Precision')
    axes[1, 0].legend()
    axes[1, 0].grid(True)
    
    # Recall
    axes[1, 1].plot(history.history['recall'], label='Train Recall')
    axes[1, 1].plot(history.history['val_recall'], label='Val Recall')
    axes[1, 1].set_title('Model Recall')
    axes[1, 1].set_xlabel('Epoch')
    axes[1, 1].set_ylabel('Recall')
    axes[1, 1].legend()
    axes[1, 1].grid(True)
    
    plt.tight_layout()
    plt.savefig(Config.HISTORY_PLOT, dpi=300, bbox_inches='tight')
    print(f"Saved training history plot: {Config.HISTORY_PLOT}")
    plt.close()

def plot_confusion_matrix(cm, class_names=['SELL', 'BUY']):
    """Plot confusion matrix"""
    print(f"Generating confusion matrix plot...")
    
    plt.figure(figsize=(8, 6))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', 
                xticklabels=class_names, yticklabels=class_names)
    plt.title('Confusion Matrix')
    plt.ylabel('True Label')
    plt.xlabel('Predicted Label')
    plt.tight_layout()
    plt.savefig(Config.CONFUSION_MATRIX_PLOT, dpi=300, bbox_inches='tight')
    print(f"Saved confusion matrix plot: {Config.CONFUSION_MATRIX_PLOT}")
    plt.close()

def save_evaluation_report(eval_results, training_time):
    """Save evaluation report to text file"""
    with open(Config.EVALUATION_REPORT, 'w') as f:
        f.write("="*60 + "\n")
        f.write("NEURAL NETWORK TRAINING REPORT\n")
        f.write("="*60 + "\n\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        
        f.write("Training Configuration:\n")
        f.write(f"  Data File: {Config.DATA_FILE}\n")
        f.write(f"  Epochs: {Config.EPOCHS}\n")
        f.write(f"  Batch Size: {Config.BATCH_SIZE}\n")
        f.write(f"  Learning Rate: {Config.LEARNING_RATE}\n")
        f.write(f"  Dropout Rate: {Config.DROPOUT_RATE}\n")
        f.write(f"  L2 Regularization: {Config.L2_REG}\n\n")
        
        f.write(f"Training Time: {training_time:.2f} seconds\n\n")
        
        f.write("Test Set Performance:\n")
        f.write(f"  Accuracy:  {eval_results['accuracy']*100:.2f}%\n")
        f.write(f"  Precision: {eval_results['precision']*100:.2f}%\n")
        f.write(f"  Recall:    {eval_results['recall']*100:.2f}%\n\n")
        
        cm = eval_results['confusion_matrix']
        f.write("Confusion Matrix:\n")
        f.write(f"  True Negatives (SELL):  {cm[0][0]}\n")
        f.write(f"  False Positives:        {cm[0][1]}\n")
        f.write(f"  False Negatives:        {cm[1][0]}\n")
        f.write(f"  True Positives (BUY):   {cm[1][1]}\n\n")
        
        f.write("="*60 + "\n")
    
    print(f"Saved evaluation report: {Config.EVALUATION_REPORT}")

def main():
    """Main training pipeline"""
    print("="*60)
    print("NEURAL NETWORK TRAINING FOR MT5 PREDICTOR")
    print("="*60)
    
    # Check TensorFlow GPU availability
    gpus = tf.config.list_physical_devices('GPU')
    if gpus:
        print(f"\n✅ GPU Available: {len(gpus)} device(s)")
        for gpu in gpus:
            print(f"   - {gpu.name}")
    else:
        print("\n⚠️  No GPU detected, using CPU (will be slower)")
    
    # Load data
    X, y = load_data(Config.DATA_FILE)
    
    # Determine architecture based on input size
    input_dim = X.shape[1]
    if input_dim == 25:
        architecture = Config.SINGLE_TF_ARCH
        print("\n📊 Detected: Single Timeframe Mode (25 features)")
    elif input_dim == 75:
        architecture = Config.MULTI_TF_ARCH
        print("\n📊 Detected: Multi-Timeframe Mode (75 features)")
    else:
        print(f"\n⚠️  Unexpected input dimension: {input_dim}")
        print("Using custom architecture based on input size...")
        architecture = [input_dim*2, input_dim, input_dim//2]
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=Config.TEST_SIZE, random_state=Config.RANDOM_STATE, stratify=y
    )
    
    # Further split training into train/validation
    X_train, X_val, y_train, y_val = train_test_split(
        X_train, y_train, test_size=0.2, random_state=Config.RANDOM_STATE, stratify=y_train
    )
    
    # Create model
    model = create_model(input_dim, architecture, Config.DROPOUT_RATE, Config.L2_REG)
    
    # Train model
    start_time = datetime.now()
    history = train_model(model, X_train, y_train, X_val, y_val)
    training_time = (datetime.now() - start_time).total_seconds()
    
    # Evaluate model
    eval_results = evaluate_model(model, X_test, y_test)
    
    # Plot results
    plot_training_history(history)
    plot_confusion_matrix(np.array(eval_results['confusion_matrix']))
    
    # Save evaluation report
    save_evaluation_report(eval_results, training_time)
    
    # Save model
    print(f"\n💾 Saving model to {Config.MODEL_OUTPUT}...")
    model.save(Config.MODEL_OUTPUT)
    print("✅ Model saved successfully!")
    
    print("\n" + "="*60)
    print("TRAINING COMPLETE!")
    print("="*60)
    print(f"\nNext steps:")
    print(f"1. Review training plots: {Config.HISTORY_PLOT}")
    print(f"2. Check evaluation report: {Config.EVALUATION_REPORT}")
    print(f"3. Run weight converter: python convert_weights.py")
    print(f"4. Copy converted weights to MT5 EA")
    print("="*60)

if __name__ == "__main__":
    main()

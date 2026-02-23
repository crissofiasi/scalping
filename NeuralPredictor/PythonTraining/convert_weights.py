"""
Weight Converter: TensorFlow/Keras to MQL5 Format
Converts trained neural network weights from Python to MQL5-compatible format
"""

import numpy as np
import tensorflow as tf
from tensorflow import keras
import json
import struct
import os

class WeightConverter:
    """Converts TensorFlow model weights to MQL5 .nnw format"""
    
    def __init__(self, model_path):
        """
        Initialize converter with trained model
        
        Args:
            model_path: Path to saved Keras model (.h5 file)
        """
        print(f"Loading model from {model_path}...")
        self.model = keras.models.load_model(model_path)
        print("✅ Model loaded successfully")
        
    def extract_weights(self):
        """Extract weights and biases from all Dense layers"""
        weights_data = {
            'layers': [],
            'architecture': [],
            'activation': 'swish',  # Default activation
            'model_info': {
                'framework': 'TensorFlow/Keras',
                'input_dim': None,
                'output_dim': 1
            }
        }
        
        layer_count = 0
        
        for layer in self.model.layers:
            # Only process Dense layers (ignore BatchNorm, Dropout, etc.)
            if isinstance(layer, keras.layers.Dense):
                layer_weights = layer.get_weights()
                
                if len(layer_weights) == 2:  # Weights + bias
                    W, b = layer_weights
                    
                    print(f"\nLayer {layer_count+1}: {layer.name}")
                    print(f"  Weights shape: {W.shape}")
                    print(f"  Bias shape: {b.shape}")
                    print(f"  Activation: {layer.activation.__name__}")
                    
                    # Store layer info
                    layer_info = {
                        'name': layer.name,
                        'type': 'dense',
                        'input_size': W.shape[0],
                        'output_size': W.shape[1],
                        'activation': layer.activation.__name__,
                        'weights': W.tolist(),  # Convert numpy to list
                        'bias': b.tolist()
                    }
                    
                    weights_data['layers'].append(layer_info)
                    weights_data['architecture'].append(W.shape[1])
                    
                    # Set input dimension from first layer
                    if layer_count == 0:
                        weights_data['model_info']['input_dim'] = W.shape[0]
                    
                    layer_count += 1
        
        # Remove output layer size from architecture (it's always 1)
        weights_data['architecture'] = weights_data['architecture'][:-1]
        
        print(f"\n✅ Extracted {layer_count} layers")
        print(f"Architecture: {weights_data['model_info']['input_dim']} -> "
              f"{weights_data['architecture']} -> 1")
        
        return weights_data
    
    def save_to_json(self, weights_data, output_path):
        """Save weights to JSON format (human-readable)"""
        print(f"\nSaving weights to JSON: {output_path}")
        
        with open(output_path, 'w') as f:
            json.dump(weights_data, f, indent=2)
        
        file_size = os.path.getsize(output_path) / 1024  # KB
        print(f"✅ JSON file saved: {file_size:.2f} KB")
    
    def save_to_binary(self, weights_data, output_path):
        """
        Save weights to binary .nnw format (MQL5 compatible)
        
        Binary format:
        - 4 bytes: magic number (0x4E4E5720 = "NNW ")
        - 4 bytes: version (1)
        - 4 bytes: number of layers
        - For each layer:
            - 4 bytes: input size
            - 4 bytes: output size
            - N * 8 bytes: weights (double)
            - M * 8 bytes: bias (double)
        """
        print(f"\nSaving weights to binary: {output_path}")
        
        with open(output_path, 'wb') as f:
            # Header
            magic = 0x4E4E5720  # "NNW "
            version = 1
            num_layers = len(weights_data['layers'])
            
            f.write(struct.pack('III', magic, version, num_layers))
            
            # Write each layer
            for layer in weights_data['layers']:
                input_size = layer['input_size']
                output_size = layer['output_size']
                
                # Layer dimensions
                f.write(struct.pack('II', input_size, output_size))
                
                # Weights (flatten to 1D array)
                weights = np.array(layer['weights']).flatten()
                for w in weights:
                    f.write(struct.pack('d', w))
                
                # Bias
                bias = np.array(layer['bias'])
                for b in bias:
                    f.write(struct.pack('d', b))
        
        file_size = os.path.getsize(output_path) / 1024  # KB
        print(f"✅ Binary file saved: {file_size:.2f} KB")
    
    def generate_mql5_loader(self, weights_data, output_path):
        """Generate MQL5 code snippet to load weights manually"""
        print(f"\nGenerating MQL5 loader code: {output_path}")
        
        code = """//+------------------------------------------------------------------+
//| Manual Weight Loading Code for MQL5                               |
//| Copy this into your EA/Script to load Python-trained weights    |
//+------------------------------------------------------------------+

bool LoadPythonWeights(CNet &network)
{
   // Network architecture
"""
        
        # Add architecture info
        arch = weights_data['architecture']
        input_dim = weights_data['model_info']['input_dim']
        code += f"   // Input: {input_dim} features\n"
        code += f"   // Hidden: {arch}\n"
        code += f"   // Output: 1\n\n"
        
        # Generate weight loading code for each layer
        for i, layer in enumerate(weights_data['layers']):
            code += f"   // Layer {i+1}: {layer['name']}\n"
            code += f"   // Shape: [{layer['input_size']}, {layer['output_size']}]\n"
            code += "   {\n"
            
            # Weights
            W = np.array(layer['weights'])
            code += f"      double w{i}[] = {{\n"
            
            # Write weights in chunks for readability
            flat_weights = W.flatten()
            chunk_size = 10
            for j in range(0, len(flat_weights), chunk_size):
                chunk = flat_weights[j:j+chunk_size]
                code += "         "
                code += ", ".join([f"{w:.15f}" for w in chunk])
                if j + chunk_size < len(flat_weights):
                    code += ",\n"
                else:
                    code += "\n"
            
            code += "      };\n\n"
            
            # Bias
            b = np.array(layer['bias'])
            code += f"      double b{i}[] = {{\n         "
            code += ", ".join([f"{bi:.15f}" for bi in b])
            code += "\n      };\n\n"
            
            # Load into network
            code += f"      // Load weights into layer {i}\n"
            code += f"      if(!network.SetLayerWeights({i}, w{i}, b{i}))\n"
            code += "      {\n"
            code += f"         Print(\"ERROR: Failed to load weights for layer {i}\");\n"
            code += "         return false;\n"
            code += "      }\n"
            code += "   }\n\n"
        
        code += """   Print("✅ Python weights loaded successfully!");
   return true;
}
"""
        
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(code)
        
        print(f"✅ MQL5 loader code generated")
    
    def verify_weights(self, weights_data):
        """Verify weight statistics"""
        print("\n" + "="*60)
        print("WEIGHT VERIFICATION")
        print("="*60)
        
        for i, layer in enumerate(weights_data['layers']):
            W = np.array(layer['weights'])
            b = np.array(layer['bias'])
            
            print(f"\nLayer {i+1}: {layer['name']}")
            print(f"  Weights: min={W.min():.6f}, max={W.max():.6f}, "
                  f"mean={W.mean():.6f}, std={W.std():.6f}")
            print(f"  Bias:    min={b.min():.6f}, max={b.max():.6f}, "
                  f"mean={b.mean():.6f}, std={b.std():.6f}")
            
            # Check for anomalies
            if np.any(np.isnan(W)) or np.any(np.isnan(b)):
                print("  ⚠️ WARNING: NaN values detected!")
            if np.any(np.isinf(W)) or np.any(np.isinf(b)):
                print("  ⚠️ WARNING: Infinite values detected!")
            if W.std() < 0.001:
                print("  ⚠️ WARNING: Very low weight variance (network may not be trained)")
        
        print("\n" + "="*60)

def main():
    """Main conversion pipeline"""
    print("="*60)
    print("TENSORFLOW TO MQL5 WEIGHT CONVERTER")
    print("="*60)
    
    # Configuration
    MODEL_INPUT = "trained_model.h5"
    JSON_OUTPUT = "model_weights.json"
    BINARY_OUTPUT = "model_weights.nnw"
    MQL5_CODE_OUTPUT = "load_python_weights.mq5"
    
    # Check if model exists
    if not os.path.exists(MODEL_INPUT):
        print(f"\n❌ ERROR: Model file not found: {MODEL_INPUT}")
        print("Please train the model first using train_nn.py or train_nn.ipynb")
        return
    
    # Initialize converter
    converter = WeightConverter(MODEL_INPUT)
    
    # Extract weights
    weights_data = converter.extract_weights()
    
    # Verify weights
    converter.verify_weights(weights_data)
    
    # Save in multiple formats
    print("\n" + "="*60)
    print("SAVING WEIGHTS")
    print("="*60)
    
    # JSON format (human-readable, for debugging)
    converter.save_to_json(weights_data, JSON_OUTPUT)
    
    # Binary format (compact, for production)
    converter.save_to_binary(weights_data, BINARY_OUTPUT)
    
    # MQL5 code snippet (manual integration)
    converter.generate_mql5_loader(weights_data, MQL5_CODE_OUTPUT)
    
    # Summary
    print("\n" + "="*60)
    print("CONVERSION COMPLETE!")
    print("="*60)
    print(f"\nGenerated files:")
    print(f"1. {JSON_OUTPUT} - Human-readable JSON format")
    print(f"2. {BINARY_OUTPUT} - Binary format for MQL5")
    print(f"3. {MQL5_CODE_OUTPUT} - MQL5 code snippet for manual loading")
    
    print(f"\nNext steps:")
    print(f"1. Option A: Copy {BINARY_OUTPUT} to MT5 Common Files folder:")
    print(f"   C:\\Users\\YourUser\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files\\")
    print(f"\n2. Option B: Use the code in {MQL5_CODE_OUTPUT} to manually load weights")
    print(f"\n3. Configure EA to use these weights instead of MQL5-trained model")
    print(f"\n4. Test in Strategy Tester!")
    print("="*60)

if __name__ == "__main__":
    main()

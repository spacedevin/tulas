//! Basic Burn-MLX tensor demo (no model required).
//! Run: cargo run --example basic_mlx --features burn-mlx

use burn::tensor::backend::Backend;
use burn::tensor::Tensor;
use burn_mlx::{Mlx, MlxDevice};

fn run_mlx_computation<B: Backend>(device: &B::Device) {
    let tensor1: Tensor<B, 2> = Tensor::from_floats([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]], device);
    let tensor2: Tensor<B, 2> = Tensor::from_floats([[7.0, 8.0], [9.0, 10.0], [11.0, 12.0]], device);
    let result = tensor1.matmul(tensor2);
    println!("MLX Matrix multiply result:\n{}", result);
}

fn main() {
    let device = MlxDevice::Gpu;
    println!("Burn-MLX on device: {:?}", device);
    run_mlx_computation::<Mlx>(&device);
}

-- Create Products Table
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    category VARCHAR(100),
    image_url VARCHAR(500),
    stock_quantity INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample products
INSERT INTO products (name, description, price, category, image_url, stock_quantity) VALUES
('Laptop Pro 15"', 'High-performance laptop with 16GB RAM and 512GB SSD', 1299.99, 'Electronics', 'https://images.unsplash.com/photo-1496181133206-80ce9b88a853?w=400', 10),
('Wireless Headphones', 'Noise-cancelling wireless headphones with 30-hour battery life', 199.99, 'Electronics', 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=400', 25),
('Smart Watch', 'Fitness tracker with heart rate monitor and GPS', 299.99, 'Electronics', 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400', 15),
('Coffee Maker', 'Automatic drip coffee maker with programmable timer', 89.99, 'Kitchen', 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=400', 8),
('Running Shoes', 'Lightweight running shoes with cushioned sole', 129.99, 'Sports', 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=400', 20),
('Backpack', 'Waterproof backpack with laptop compartment', 79.99, 'Accessories', 'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=400', 12),
('Bluetooth Speaker', 'Portable speaker with 360-degree sound', 149.99, 'Electronics', 'https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?w=400', 18),
('Desk Lamp', 'LED desk lamp with adjustable brightness', 49.99, 'Home', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400', 30);

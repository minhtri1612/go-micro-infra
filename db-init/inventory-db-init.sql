CREATE TABLE IF NOT EXISTS inventory (
    id SERIAL PRIMARY KEY,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    sku VARCHAR(50) NOT NULL,
    location VARCHAR(100)
);

-- Insert sample inventory data
INSERT INTO inventory (product_id, quantity, sku, location) VALUES
(1, 10, 'LAPTOP001', 'Warehouse A'),
(2, 25, 'HEADPHONE001', 'Warehouse A'),
(3, 15, 'WATCH001', 'Warehouse A'),
(4, 8, 'COFFEE001', 'Warehouse B'),
(5, 20, 'SHOES001', 'Warehouse B'),
(6, 12, 'BACKPACK001', 'Warehouse A'),
(7, 18, 'SPEAKER001', 'Warehouse A'),
(8, 30, 'LAMP001', 'Warehouse B');

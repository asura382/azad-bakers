-- Optional: run after api-grants.sql and after your owner account has been
-- inserted into admin_users. Safe to skip and enter real products from the UI.
insert into public.products (name, category, description, price, image_url, badge, active, sort_order)
select * from (values
('Celebration Cake','Cakes','Soft vanilla sponge, creamy frosting and colourful sprinkles.',899,'','Birthday favourite',true,10),
('Chocolate Ganache Cake','Cakes','Rich chocolate layers finished with silky ganache.',1199,'','Chocolate',true,20),
('Mango Cream Cake','Cakes','Light vanilla sponge with fresh mango and cream.',999,'','Seasonal',true,30),
('Red Velvet Cake','Cakes','Velvety cocoa sponge with a smooth cream finish.',1099,'','Celebration',true,40),
('Fresh Pastry Box','Pastries','A mixed box of bakery favourites for sharing.',299,'','For sharing',true,50),
('Tea-Time Cookies','Bakery','Crisp, buttery bites made for your evening chai.',199,'','Tea time',true,60)
) as x(name,category,description,price,image_url,badge,active,sort_order)
where not exists (select 1 from public.products);

# Ozie

## About This App
Ozie is a mobile app that helps businesses manage deliveries, track their sales team, and handle orders smoothly. It connects delivery staff, shop owners, and managers in one place so everyone can see what is happening in real time.

## Main Features
- **Live delivery tracking**: See where delivery staff are on a map while they are on their way.
- **Order management**: Receive new orders, update their status, and keep everyone informed.
- **Sales team tracking**: Managers can see where their sales team is and what they are doing.
- **Safe payments**: Collect payments for orders easily within the app.
- **Instant notifications**: Get quick messages about new orders, delivery updates, and important news.
- **Shop and customer records**: Keep a simple record of shops, customers, and their order history.
- **Route guidance**: Delivery staff can find the best way to reach their destination.

## How It Works
1. A customer or shop places an order.
2. The order appears in the app for the delivery team.
3. A delivery person accepts the order and picks it up.
4. The manager and customer can watch the delivery person move on the map.
5. Once delivered, the order is marked complete and payment is collected.
6. Everyone receives updates at each step so nothing is missed.

## Who Can Use This App
- Delivery teams
- Sales representatives
- Shop owners
- Business managers

---

## 🏪 Retailer Features

Niche **Retailer side** me jo jo features banaye gaye hain, unki complete list hai. Saare features `v1/retailer/*` API endpoints par chalte hain.

### 1. Retailer Onboarding / Registration (`retailer_form_screen.dart`)
- Naya retailer self-register kar sakta hai: shop name, license number, contact, email, address (building, street, landmark, city, pincode), brands jo bechna hai, monthly purchase cases aur oftake details.
- Data `v1/onboarding/submit` par bhejte hain.

### 2. Product Catalog (`catalog_screen.dart`, `tabs/catalog_tab.dart`)
- Sare products browse karna (search, category filter, brand filter).
- Product par click karke detail dekhna.
- Wishlist mein add/remove karna (`toggle_wishlist`).
- Search bar se products dhoondna.

### 3. Cart (`cart_screen.dart`)
- Product ko cart mein add karna (`add_to_cart`).
- Cart mein quantity increase/decrease karna (plus/minus).
- Item remove karna (`delete`).
- Coupon / Scheme apply karna (per-product ya all-products offer, min qty check).
- Cart summary: subtotal, savings, net payable.
- "Explore More" brand-wise product suggestions.

### 4. Checkout & Payment (`checkout_screen.dart`, `razorpay_service.dart`)
- Checkout summary: payable amount, available credit, billing/shipping address.
- Payment method choose karna:
  - **Online** — Razorpay se UPI/Card/Net Banking payment.
  - **Credit Limit** — Available credit limit se payment.
  - **Cash on Delivery** — Delivery par cash payment.
- Order place karna (`place_order`). Online payment pehle Razorpay se confirm hota hai, phir order place hota hai.

### 5. Order Tracking — "Where is my order" (`where_is_my_order_screen.dart`)
- Abhi place huye order ka status timeline: Order Placed → Approved → Packing → Dispatched → Delivered.
- Recent approved orders ki list.

### 6. Invoices (`invoices_screen.dart`, `invoice_view_screen.dart`)
- Sare invoices ki list (search, status filter: paid/pending/unpaid/partial/requested, date filter: today/week/month/all).
- Invoice detail view aur share karna.

### 7. Pending Payments (`pending_payments_screen.dart`)
- Unpaid / partial / requested invoices ki list.
- Distributor/salesman ko payment collect karne ki request bhejna (`send_pay_request`).
- Online payment success ke baad verify karna (`verify_payment`).

### 8. Reports / Analytics (`reports_screen.dart`)
- Sales totals, top products, offers, 30-day sales chart (CustomPaint se bana, koi extra package nahi).

### 9. Finance — Bank Loan (`finance_screen.dart`)
- Loan applications ki list (pending + completed).
- Naya loan application submit karna: bank name, company name, PAN, GST, turnover, loan requirement, address etc. (`v1/retailer/loan-applications`).

### 10. Schemes / Coupons (`schemes_screen.dart`)
- Active schemes ki list: discount percent, flat per case, min qty.
- Cart mein scheme apply karna.

### 11. Returns (`returns_screen.dart`, `return_form_screen.dart`)
- Return history: status filter (Pending, Approved, Claimed, Rejected).
- Naya return request submit karna (invoice, reason, resolution type: credit note ya replacement).
- Approved return ko claim karna (credit note add ya replacement items cart mein add).

### 12. Dispatch / Packing / Received (`dispatch_screen.dart`, `packing_screen.dart`, `received_screen.dart`)
- Packing orders: approved orders jo packing mein hain.
- Dispatch history: kis order ko dispatch kiya gaya.
- Received history: jo order receive chuke hain, unhe mark received karna (`condition_accepted`).

### 13. Support Tickets (`support_tickets_screen.dart`, `support_ticket_form_screen.dart`)
- Ticket history (newest first).
- Naya ticket submit karna (type, subject, description, optional attachment).
- Ticket ko rate karna (satisfied / unsatisfied).

### 14. Notifications (`notifications_screen.dart`)
- Retailer ke notifications ki list.
- Notification ko read mark karna.

### 15. Profile / My Account (`profile_screen.dart`, `change_password_screen.dart`)
- Profile detail: name, shop, address, city, state, pincode.
- Profile edit aur update karna.
- Change password.

### 16. Promo Banners
- Active promo banners dikhna (`v1/retailer/banners`).
- Banner se product direct cart mein add karna.

---

### 🔗 Retailer API Endpoints (`retailer_service.dart`)

| Endpoint | Kaam |
|----------|------|
| `v1/retailer/products` | Catalog, wishlist toggle, add to cart |
| `v1/retailer/orders` | Orders list |
| `v1/retailer/review-orders` | Draft order: delete item, save qty, preview |
| `v1/retailer/notifications` | Notifications list, mark read |
| `v1/retailer/schemes` | Schemes / coupons list |
| `v1/retailer/cart` | Cart CRUD |
| `v1/retailer/checkout` | Checkout summary, place order |
| `v1/retailer/reports` | Sales reports |
| `v1/retailer/pending-payments` | Pending payments, collection request, verify payment |
| `v1/retailer/invoices` | Invoices list, invoice detail |
| `v1/retailer/dispatch-history` | Dispatch history, mark received |
| `v1/retailer/packing-orders` | Packing orders |
| `v1/retailer/received-history` | Received history |
| `v1/retailer/banners` | Promo banners, add to cart |  
| `v1/retailer/support-tickets` | Support tickets, submit, rate |
| `v1/retailer/returns` | Returns, submit return, claim return |
| `v1/retailer/loan-applications` | Loan applications, submit loan |

Ye saare features retailer ke liye bane hain taaki wo ghar baithe order place kar sake, payment track kar sake, returns manage kar sake aur support le sake.
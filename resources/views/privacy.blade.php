@component('layouts.legal', ['title' => 'Privacy Policy'])
<p>This policy explains how MADYAW (“we”, “the app”) handles information when you use the Android app and the related hotel API at this website. MADYAW is hotel operations software for properties in the Philippines. It is not an advertising product and it does not sell personal information.</p>

<h2>Who this applies to</h2>
<p>Hotel staff, hotel owners, public guests who search or book rooms, in-house guests who use a room login, and MADYAW members. If you stay at a hotel, that hotel is also a controller of the guest records it enters.</p>

<h2>Information we process</h2>
<ul>
    <li><strong>Accounts:</strong> name, username, email, password, role, and the hotel you belong to.</li>
    <li><strong>Hotel profile:</strong> property name, address, optional GPS coordinates, rooms, rates, and payment QR images.</li>
    <li><strong>Bookings and stays:</strong> guest name, phone, email, nationality, dates, room, charges, and payment status.</li>
    <li><strong>Identity and payment proofs:</strong> photos or files the front desk or guest uploads (government ID, payment screenshot). These are stored so staff can confirm the stay.</li>
    <li><strong>Location:</strong> approximate or precise location if you allow it, used to find hotels near you or to save a property’s map point at registration. Location is not used for ads.</li>
    <li><strong>Camera and files:</strong> only when you choose to scan a QR code or attach an ID / payment image.</li>
    <li><strong>Messages:</strong> in-app chat between guests, hotel staff, and MADYAW support, including optional attachments.</li>
    <li><strong>Device SMS (staff only):</strong> after check-in the app can open the phone’s Messages app with a welcome text. You tap Send. MADYAW does not send SMS in the background and does not read your message inbox.</li>
    <li><strong>Technical logs:</strong> app and server logs needed to keep the service running and to diagnose errors.</li>
</ul>

<h2>How we use it</h2>
<p>We use this information to operate hotel check-in and checkout, online booking, room access, billing, membership points, hotel credit wallets, support chat, and security (sign-in, password reset, and abuse prevention). We do not use it to show third-party ads or to build advertising profiles.</p>

<h2>Who we share it with</h2>
<ul>
    <li><strong>The hotel you booked or work for</strong> — staff see guest and stay data for that property only.</li>
    <li><strong>Payment processors</strong> (for example PayMongo or Xendit) when you pay a deposit, stay, or hotel credit recharge.</li>
    <li><strong>Email delivery</strong> for one-time codes, password resets, and stay notices, when email is enabled.</li>
    <li><strong>Hosting and database providers</strong> that run the API and store records (currently the production API host and MongoDB).</li>
</ul>
<p>We do not sell personal information. We do not share data with advertising networks. The app does not collect an advertising ID.</p>

<h2>Retention</h2>
<p>We keep account, booking, payment, and uploaded files for as long as the hotel account is active and as needed for operations, disputes, and legal duties. Hotels can ask us to close an account; guest-facing deletion requests should go to the hotel that took the booking, or to us if the request is about a MADYAW member account.</p>

<h2>Security</h2>
<p>Access uses encrypted HTTPS in production, staff and guest tokens, and hotel-scoped records. Uploaded IDs and payment proofs are sensitive: treat front-desk devices as confidential and lock staff accounts.</p>

<h2>Children</h2>
<p>MADYAW is built for adult hotel staff and adult guests. It is not directed at children under 18. Do not create an account for a child.</p>

<h2>Your choices</h2>
<p>You can deny camera or location permission; nearby-hotel search and QR / photo features will be limited. You can close the Messages composer without sending a welcome text. You can request access or correction of your MADYAW account by contacting us through in-app <strong>Chat with MADYAW</strong> (hotel admin) or the email on the Google Play listing.</p>

<h2>Contact</h2>
<p>Privacy questions: use Chat with MADYAW in the app, or the developer contact email shown on the Google Play store listing for MADYAW.</p>
@endcomponent

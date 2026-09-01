@component('layouts.legal', ['title' => 'Privacy & Terms'])
<p>This page is the privacy policy and terms of service for the <strong>MADYAW</strong> Android app and the hotel API on this website. By creating an account, signing in, or completing a booking you agree to these terms. If you do not agree, do not use the service.</p>
<p>MADYAW is hotel operations software. It is not an advertising product and it does not sell personal information. Account deletion: <a href="{{ url('/account-deletion') }}">{{ url('/account-deletion') }}</a>.</p>

<h2 id="privacy">Privacy policy</h2>
<p>This section explains how MADYAW (“we”, “the app”) handles information.</p>

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
<p>We keep account, booking, payment, and uploaded files for as long as the hotel account is active and as needed for operations, disputes, and legal duties. To close a MADYAW member or hotel account, use <a href="{{ url('/account-deletion') }}">Delete your MADYAW account</a>. Guest stay records entered by a hotel should be requested from that hotel first.</p>

<h2>Security</h2>
<p>Access uses encrypted HTTPS in production, staff and guest tokens, and hotel-scoped records. Uploaded IDs and payment proofs are sensitive: treat front-desk devices as confidential and lock staff accounts.</p>

<h2>Children</h2>
<p>MADYAW is built for adult hotel staff and adult guests. It is not directed at children under 18. Do not create an account for a child.</p>

<h2>Your choices</h2>
<p>You can deny camera or location permission; nearby-hotel search and QR / photo features will be limited. You can close the Messages composer without sending a welcome text. You can request access, correction, or deletion of your MADYAW account from the app (<strong>Delete account</strong>) or at <a href="{{ url('/account-deletion') }}">{{ url('/account-deletion') }}</a>.</p>

<h2 id="terms">Terms of service</h2>
<p>These terms govern use of the MADYAW Android app and the hotel API on this website.</p>

<h2>What MADYAW is</h2>
<p>MADYAW is software for hotels: property setup, staff sign-in, front-desk check-in and checkout, guest room access, public room search and booking, membership, hotel credit wallets, and related messages. We provide the platform. Each hotel is responsible for its rooms, prices, guest records, and how it treats guests.</p>

<h2>Accounts</h2>
<p>Hotel staff and owners must keep sign-in details confidential and use the app only for their assigned property. Guests must use room or member credentials only for their own stay. You are responsible for activity under your account. We may suspend access for abuse, unpaid hotel subscription or credits, or security risk. To close your account, tap <strong>Delete account</strong> in the app. That sends a request to MADYAW central admin, who confirms before the account is removed. Details: <a href="{{ url('/account-deletion') }}">Delete your MADYAW account</a>.</p>

<h2>Bookings and payments</h2>
<p>Rates, deposits, refunds, and house rules are set by the hotel (and by payment processors for card or e-wallet charges). Online bookings may require a deposit. Front-desk check-in may require ID and payment proof. Hotel credit wallet fees and subscriptions are charged according to the hotel’s MADYAW settings and the amounts shown in the app. Failed, pending, or reversed payments can change booking status.</p>

<h2>Acceptable use</h2>
<p>Do not probe or disrupt the API, impersonate another person or hotel, upload unlawful content, or use the app to harm guests or staff. Do not scrape listings for a competing service.</p>

<h2>Messages and SMS</h2>
<p>In-app chat is for stay and support matters. After check-in, staff may open the device Messages app to send a welcome text. The staff member is the sender of that SMS and must have a lawful reason to contact the guest.</p>

<h2>Availability</h2>
<p>We aim to keep the service available but do not guarantee uninterrupted uptime. Hosting, payments, or email providers can fail. Hotels should keep a fallback process for walk-in check-in if the internet is down.</p>

<h2>Liability</h2>
<p>To the extent allowed by law, MADYAW is provided as-is. We are not liable for hotel decisions (overbooking, refunds, room condition), guest conduct, or losses from payment-provider outages. Our aggregate liability for the app is limited to the fees the affected hotel paid us for the three months before the claim, or ₱5,000 if none.</p>

<h2>Changes</h2>
<p>We may update this page. The “Last updated” date will change. Continued use after an update means you accept the new terms.</p>

<h2>Contact</h2>
<p>Questions: Chat with MADYAW in the hotel admin app, or the developer contact on the Google Play listing.</p>
@endcomponent

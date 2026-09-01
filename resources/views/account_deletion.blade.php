@component('layouts.legal', ['title' => 'Delete your MADYAW account'])
<p><strong>This page is for the MADYAW Android app</strong> (developer listing name: MADYAW). Use it to request that we delete your account and the personal data we hold for that account.</p>

<h2>How to request deletion</h2>
<p>There is no self-serve delete button. Follow these steps. We aim to finish a valid request within <strong>30 days</strong>.</p>
<ol>
    <li>Open the <strong>MADYAW</strong> app on your phone.</li>
    <li>If you work at a hotel: sign in to that property, open <strong>Settings</strong>, then tap <strong>Chat with MADYAW</strong>. Write that you want your account deleted. Include the hotel name, your username, and the email on the account.</li>
    <li>If you are a MADYAW member (guest bookings): sign in, then use in-app chat with the hotel or the developer contact email on the Google Play listing for MADYAW. Write that you want your MADYAW member account deleted. Include your name, email, and username if you have one.</li>
    <li>If you cannot open the app, email the developer contact shown on the MADYAW Google Play store listing. Use the subject <strong>MADYAW account deletion</strong> and include the same details as above.</li>
    <li>We will confirm the request (we may ask you to prove you own the account), then delete or anonymize the data listed below.</li>
</ol>

<h2>Guest stay records at a hotel</h2>
<p>If your request is only about a stay (name, ID photo, payment screenshot, room login), contact that hotel first. The hotel entered those records and is responsible for them. You can still write to MADYAW if the hotel does not help, or if you also want a MADYAW member account removed.</p>

<h2>Data we delete</h2>
<p>When we close your MADYAW account we delete or irreversibly anonymize:</p>
<ul>
    <li>Sign-in details: name, username, email, password, and role on that account</li>
    <li>MADYAW member profile and membership points tied to that account</li>
    <li>In-app chat with MADYAW support that you sent from that account, including attachments where we store them</li>
    <li>Device tokens and session tokens for that account so you cannot sign in again</li>
</ul>
<p>If a hotel owner asks us to close the <strong>whole property</strong>, we also remove that hotel’s MADYAW workspace (staff logins, rooms, rates, and hotel credit wallet in our systems), except the records we must keep as described next.</p>

<h2>Data we keep, and for how long</h2>
<ul>
    <li><strong>Hotel stay and booking files the property still needs</strong> (guest names, dates, charges, ID or payment proofs): kept by the hotel for operations, disputes, and legal duties. We do not wipe another hotel’s legal records just because a guest deletes a member login. The hotel decides retention for those files.</li>
    <li><strong>Payment and billing records</strong> (credit recharges, subscription invoices, processor references): kept as required for tax, fraud, and payment-provider rules, then deleted or anonymized. This is typically up to <strong>five years</strong>.</li>
    <li><strong>Security and server logs</strong> that may still mention an account id: dropped from active systems when we delete the account; copies in backups are overwritten within <strong>90 days</strong>.</li>
    <li><strong>Legal holds:</strong> if we must keep data for an investigation, court order, or unpaid dispute, we keep only what the law requires until that matter ends, then delete or anonymize it.</li>
</ul>
<p>We do not use leftover data for ads. MADYAW does not sell personal information.</p>

<h2>What happens after deletion</h2>
<p>You will not be able to sign in. A hotel that still operates on MADYAW can create a new staff account later. Bookings already completed stay in the hotel’s history as above. Payment processors (for example PayMongo or Xendit) keep their own copies under their policies.</p>

<p>Privacy policy: <a href="{{ url('/privacy') }}">{{ url('/privacy') }}</a></p>
@endcomponent

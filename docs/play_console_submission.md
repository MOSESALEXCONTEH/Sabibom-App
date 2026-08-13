# Google Play Console Submission

## App access

SabiBom requires authentication. Create a dedicated reviewer account with a demo business and non-sensitive demo data. Keep it active throughout review.

Provide Play reviewers:

- Email and password for the reviewer account
- Instruction: sign in, select Demo Business, and use Main Branch
- Confirmation that no OTP, external approval, or paid subscription is required
- A support contact monitored during review

Never provide an owner account containing real production data.

## Content declarations

- Ads: No, unless an advertising SDK or paid placement is added before submission
- App category: Business
- Target audience: adults/business operators; not designed for children
- News app: No
- Government app: No
- Financial features: business record keeping and reporting only; not banking, lending, investment, money transfer or financial advice
- Health features: None identified

## Release sequence

1. Create app with package `com.sabibom.app`.
2. Enroll in Play App Signing.
3. Upload the signed `1.0.0+1` AAB to Internal testing.
4. Add the Play app-signing SHA-256 certificate to Firebase Android App Check and any OAuth configuration that requires it.
5. Install exclusively from the internal-test Play link and run the physical acceptance matrix.
6. Complete App content, Data Safety, content rating, target audience and store listing.
7. Complete the required closed test if the account is subject to the 12-testers/14-days rule.
8. Apply for production access, then submit production rollout for review.

## Links

- Privacy: `https://sabibom.com/privacy`
- Terms: `https://sabibom.com/terms`
- Deletion: `https://sabibom.com/delete-account`
- Support: `https://sabibom.com/support`

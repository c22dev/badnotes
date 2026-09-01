# BadNotes
an iOS tweak that unlocks Goodnotes Pro

## How does this works ?

Goodnotes uses RevenueCat to manage subscriptions. Every time the app starts, it sends a request to a GoodNotes proxied RevenueCat's API (`/v1/subscribers/<user_id>`) to check your subscription status

BadNotes hooks `NSURLSession`'s `dataTaskWithRequest:completionHandler:` at runtime ; and when the app makes a request to that endpoint, the tweak intercepts the response and replaces the JSON body with a crafted payload that tells the app u are Pro

That's basically it !

## Limitations

Some features are server-side and won't work (AI features, collaboration, etc...)

## Building

```
xcrun clang -arch arm64 -shared -fobjc-arc -install_name @executable_path/BadNotes.dylib -framework Foundation -o BadNotes.dylib Tweak.m
```

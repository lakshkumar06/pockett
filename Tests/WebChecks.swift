import Foundation
@main struct WebChecks {
    static func main() throws {
        let payment = "solana:So11111111111111111111111111111111111111112?amount=0.001&label=Dues"
        precondition(WebPolicy.solanaPayment(URL(string: payment)!))
        for value in [payment + "&amount=2", payment + "&secret=x", payment + "#access=secret", "solana:https://evil.example/tx", "solana:So11111111111111111111111111111111111111112?amount=0", "solana:So11111111111111111111111111111111111111112?amount=1e3"] {
            precondition(!WebPolicy.solanaPayment(URL(string: value)!))
        }
        let entry = URL(string: "https://notes.example/app")!
        for value in ["https://notes.example/next", "https://notes.example:443/a?view=full#note"] { precondition(WebPolicy.safe(URL(string:value)!,for:entry)) }
        for value in ["https://evil.example/app", "http://notes.example/app", "https://notes.example:444/", "https://user:pass@notes.example/", "javascript:alert(1)"] { precondition(!WebPolicy.safe(URL(string:value)!,for:entry)) }
        precondition(!WebPolicy.restorable(URL(string:"https://notes.example/callback?code=private")!,for:entry))
        precondition(DeepLink(url: URL(string:"pocket://app/id?event=event_42")!) == .event(app:"id",event:"event_42"))
        for link in ["pocket://app/id?event=a&url=https://evil.example", "pocket://app/id?event=", "pocket://app/id?event=../escape"] { precondition(DeepLink(url:URL(string:link)!) == nil) }
        let fixture = URL(fileURLWithPath:"Developer/Contracts/web-v1/fixtures/flow.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf:fixture)) as! [String:Any]
        let inbox = try JSONDecoder().decode(InboxReply.self,from: JSONSerialization.data(withJSONObject:object["inbox"]!))
        let launch = try JSONDecoder().decode(NotificationLaunch.self,from:JSONSerialization.data(withJSONObject:object["launch"]!))
        precondition(inbox.entries[0].target == launch.target && WebPolicy.safe(launch.url,for:entry))
        print("Safe launch, deep-link and shared notification fixture checks passed")
    }
}

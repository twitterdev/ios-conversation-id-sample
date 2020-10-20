//
//  ShareViewController.swift
//  threadshare
//
//  Created by Daniele Bernardi on 10/15/20.
//

import UIKit
import Social
import WebKit


@objc(CustomShareNavigationController)
class CustomShareNavigationController: UINavigationController {
  
  override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    self.setViewControllers([ShareViewController()], animated: false)
  }
  
  @available(*, unavailable)
  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }
}


class ShareViewController: UIViewController, WKNavigationDelegate {
  
  var webView: WKWebView!
  
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    webView.isHidden = false
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.view.backgroundColor = .systemGray6
    self.navigationItem.title = "Thread"
    
    let itemDone = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
    self.navigationItem.setRightBarButton(itemDone, animated: false)
    let configuration = WKWebViewConfiguration()
    configuration.dataDetectorTypes = [.link, .flightNumber, .lookupSuggestion]
    webView = WKWebView(frame: .init(x: 0, y: 0, width: 100, height: 100), configuration: configuration)
    webView.navigationDelegate = self
    webView.isHidden = true
    self.view.addSubview(webView)
    webView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
      webView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
      webView.heightAnchor.constraint(equalTo: self.view.heightAnchor),
      webView.widthAnchor.constraint(equalTo: self.view.widthAnchor)
    ])
    
    if let extensionContext = extensionContext,
       let item = extensionContext.inputItems.first as? NSExtensionItem,
       let itemProvider = item.attachments?.first {
      if itemProvider.hasItemConformingToTypeIdentifier("public.url") {
        itemProvider.loadItem(forTypeIdentifier: "public.url", options: nil) { (url, error) in
          if let shareURL = url as? URL,
             self.validateTweetURL(url: shareURL) != nil {
            self.findThread(tweetURL: shareURL)
          } else {
            let alert = UIAlertController(title: "Invalid thread", message: "This is not a valid Twitter thread, or the thread is older than seven days.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: { (UIAlertAction) in
              self.cancel()
            }))
            
            DispatchQueue.main.async {
              self.present(alert, animated: true)
            }
          }
        }
      }
    }
  }
  
  func validateTweetURL(url: URL) -> URL? {
    let pattern = #"(?:https:\/\/(?:.*\.)?twitter.com\/[\w\d_]+\/status\/)(\d{1,19})"#
    guard (url.absoluteString.range(of: pattern, options: .regularExpression) != nil) else {
      return nil
    }
    
    return url
  }
  
  func getId(tweetURL: URL) -> String {
    return tweetURL.pathComponents.last!
  }
  
  func daysBetween(start: Date, end: Date) -> Int {
    return abs(Calendar.current.dateComponents([.day], from: start, to: end).day!)
  }
  
  func formatTweetCreationDate(tweet: Tweet) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: tweet.createdAt)
  }
  
  func removeLinksFromText(tweet: Tweet) -> String {
    var text = tweet.text
    if let entities = tweet.entities,
       let urls = entities.urls {
      let displayUrls = urls.filter({ (url) in
       let pattern = #"(?:https:\/\/(?:.*\.)?twitter.com\/[\w\d_]+\/status\/)(\d{1,19})(\/photo|video)?(\/\d)?"#

        return url.expandedUrl.range(of: pattern, options: .regularExpression) != nil
      })
      
      for url in displayUrls {
        text = text.replacingOccurrences(of: url.url, with: "")
      }
      
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    return text
  }
  
  func alert(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: { (UIAlertAction) in
      self.cancel()
    }))
    DispatchQueue.main.async {
      self.present(alert, animated: true)
    }
  }
  
  func renderPoll(_ poll: Poll) -> String {
    var body: Array<String> = [];
    
    let options = poll.options.sorted { $0.position < $1.position }
    let winningOption = options.max { $0.votes < $1.votes }
    let totalVotes = options.map { $0.votes }.reduce(0, +)
    
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    
    for option in options {
      let winningOptionClass = option.position == winningOption?.position ? "win" : ""
      var percent = formatter.string(from: 0)!
      if totalVotes > 0 {
        percent = formatter.string(from: NSNumber(value: Float(option.votes) / Float(totalVotes)))!
      }
      
      body.append("""
        <article class=\"flex \(winningOptionClass)\">
          <div class=\"grow\">
            <label>\(option.label)</label>
            <progress value="\(option.votes)" max="\(totalVotes)">\(percent)</progress>
          </div>
          <div>\(percent)</div>
        </article>
      """)
    }
    return body.joined()
  }
  
  func findThread(tweetURL: URL) {
    let tweetId = getId(tweetURL: tweetURL)
    Tweet.tweet(id: tweetId) { (tweet, response, error) in
      if error != nil,
         error as? TwitterRequestError == .missingBearerToken {
        self.alert(title: "Missing Bearer token", message: "Your Bearer token is missing. Add your Bearer token in TwitterSettings.plist and build this project again.")
        return
      }
      
      guard let tweet = tweet,
            let singleResponse = response else {
        self.alert(title: "Invalid tweet", message: "This is not a valid Twitter thread, or the thread is older than seven days.")
        
        return
      }
      
      if tweet.isOlderThanSevenDays {
        self.alert(title: "Thread too old", message: "The recent search endpoint can only return conversations tweeted in the past 7 days.")

        return
      }
      
      Tweet.thread(tweet: tweet, completionBlock: { (thread, searchResponse, error) in
        if error != nil,
           error as? TwitterRequestError == .missingBearerToken {
          self.alert(title: "Missing Bearer token", message: "Your Bearer token is missing. Add your Bearer token in TwitterSettings.plist and build this project again.")
          return
        }

        var paragraphs = [String]()
        guard let thread = thread,
              let searchResponse = searchResponse else {
          let alert = UIAlertController(title: "Invalid thread", message: "This is not a valid Twitter thread, or the thread is older than seven days.", preferredStyle: .alert)
          alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: { (UIAlertAction) in
            self.cancel()
          }))
          
          DispatchQueue.main.async {
            self.present(alert, animated: true)
          }
          
          return
        }
        
        for tweetOfThread in thread {
          paragraphs.append("<p>\(self.removeLinksFromText(tweet: tweetOfThread))</p>")

          if let poll = searchResponse.poll(tweet: tweetOfThread) {
            paragraphs.append(self.renderPoll(poll))
          }

          if let media = searchResponse.media(tweet: tweetOfThread) {
            for mediaItem in media {
              if let urlString = mediaItem.type == .photo ? mediaItem.url : mediaItem.previewImageUrl {
                paragraphs.append("<p><img src=\"\(urlString)\"/></p>")
              }
            }
          }
          
          if let quotedTweet = tweetOfThread.referenceURL(type: .quoted) {
            paragraphs.append("<blockquote class=\"twitter-tweet\" data-conversation=\"none\"><a href=\"\(quotedTweet.absoluteString)\"></a></blockquote>")
          }
        }
        
        let body = paragraphs.joined()
        if let bundleURL = Bundle.main.url(forResource: "template", withExtension: "html"),
           let template = try? String(contentsOf: bundleURL),
           let user = singleResponse.user() {
          
          var html = template.replacingOccurrences(of: "{{CONTENT}}", with: body)
          html = html.replacingOccurrences(of: "{{PROFILE_IMAGE_URL}}", with: user.profileImageUrl)
          html = html.replacingOccurrences(of: "{{NAME}}", with: user.name)
          html = html.replacingOccurrences(of: "{{USERNAME}}", with: user.username)
          html = html.replacingOccurrences(of: "{{TWEET_CREATED_AT}}", with: self.formatTweetCreationDate(tweet: tweet))
          self.webView.loadHTMLString(html, baseURL: nil)
        } else {
          let alert = UIAlertController(title: "Cannot get thread", message: "The operation could not be completed. Try again later.", preferredStyle: .alert)
          alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: { (UIAlertAction) in
            self.cancel()
          }))
          
          DispatchQueue.main.async {
            self.present(alert, animated: true)
          }
          
        }
        
      })
    }
    
  }
  
  @objc func cancel() {
    let error = NSError(domain: "some.bundle.identifier", code: 0, userInfo: [NSLocalizedDescriptionKey: "An error description"])
    extensionContext?.cancelRequest(withError: error)
  }
  
  @objc func done() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
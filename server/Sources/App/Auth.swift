import JWT
import PostgresNIO
import Vapor

/// The server's own access token. 15 minutes; the phone signs in again when it expires.
struct UserToken: JWTPayload, Authenticatable {
    var sub: SubjectClaim   // users.id
    var exp: ExpirationClaim

    var userId: UUID { UUID(uuidString: sub.value)! }

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
        guard UUID(uuidString: sub.value) != nil else { throw JWTError.claimVerificationFailure(failedClaim: sub, reason: "not a user id") }
    }
}

struct TokenResponse: Content {
    var accessToken: String
    var expiresIn: Int
}

struct AuthController: RouteCollection {
    static let lifetime: TimeInterval = 15 * 60

    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("apple", use: apple)
        if Environment.get("AUTH_DEV") == "1" { auth.post("dev", use: dev) }
    }

    /// Body: { "identityToken": "<Apple JWT>" }. Checks signature, issuer, audience and expiry
    /// against Apple's published keys.
    func apple(req: Request) async throws -> TokenResponse {
        struct Body: Content { var identityToken: String }
        let body = try req.content.decode(Body.self)
        let apple = try await req.jwt.apple.verify(body.identityToken)
        return try await issue(req, subject: "apple:" + apple.subject.value)
    }

    /// Development and tests only (AUTH_DEV=1): a token for any subject, no Apple account.
    func dev(req: Request) async throws -> TokenResponse {
        struct Body: Content { var subject: String }
        let body = try req.content.decode(Body.self)
        guard !body.subject.isEmpty, body.subject.count <= 200 else { throw Abort(.badRequest) }
        return try await issue(req, subject: "dev:" + body.subject)
    }

    private func issue(_ req: Request, subject: String) async throws -> TokenResponse {
        let rows = try await req.application.db.query("""
            INSERT INTO users (apple_sub) VALUES (\(subject))
            ON CONFLICT (apple_sub) DO UPDATE SET apple_sub = EXCLUDED.apple_sub
            RETURNING id
            """, logger: req.logger)
        guard let id = try await rows.collect().first?.decode(UUID.self) else { throw Abort(.internalServerError) }
        let token = UserToken(sub: .init(value: id.uuidString), exp: .init(value: Date().addingTimeInterval(Self.lifetime)))
        return TokenResponse(accessToken: try await req.jwt.sign(token), expiresIn: Int(Self.lifetime))
    }
}

/// Puts the verified user on the request; anything else is 401. No route reads a user id
/// from the body or the URL.
struct UserAuthenticator: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        if let token = try? await request.jwt.verify(bearer.token, as: UserToken.self) {
            request.auth.login(token)
        }
    }
}

extension Request {
    func userId() throws -> UUID { try auth.require(UserToken.self).userId }
}

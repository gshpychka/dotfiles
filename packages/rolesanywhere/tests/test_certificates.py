"""The certificates module with a software key standing in for the TPM2 key:
the requirements IAM Roles Anywhere places on trust anchors and client
certificates, and that a signature from anything but the CA key is refused."""

import datetime

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID, SignatureAlgorithmOID
from rolesanywhere import certificates

NOW = datetime.datetime(2026, 10, 15, 12, 0, tzinfo=datetime.UTC)
LIFETIME = datetime.timedelta(minutes=5)


def signer(key: ec.EllipticCurvePrivateKey) -> certificates.Signer:
    return lambda message: key.sign(message, ec.ECDSA(hashes.SHA256()))


@pytest.fixture
def ca_key() -> ec.EllipticCurvePrivateKey:
    return ec.generate_private_key(ec.SECP256R1())


@pytest.fixture
def ca(ca_key: ec.EllipticCurvePrivateKey) -> x509.Certificate:
    return certificates.ca_certificate(
        "reaper", ca_key.public_key(), signer(ca_key), NOW
    )


def client(
    ca: x509.Certificate,
    ca_key: ec.EllipticCurvePrivateKey,
    now: datetime.datetime = NOW,
) -> x509.Certificate:
    key = ec.generate_private_key(ec.SECP256R1())
    return certificates.client_certificate(
        "reaper:alice", key.public_key(), ca, signer(ca_key), now, LIFETIME
    )


def test_ca_certificate(
    ca: x509.Certificate, ca_key: ec.EllipticCurvePrivateKey
) -> None:
    assert ca.version is x509.Version.v3
    assert ca.signature_algorithm_oid == SignatureAlgorithmOID.ECDSA_WITH_SHA256
    assert ca.subject == ca.issuer
    assert (
        ca.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
        == "reaper Roles Anywhere CA"
    )
    assert ca.public_key() == ca_key.public_key()
    assert certificates.issued_by(ca, ca)
    constraints = ca.extensions.get_extension_for_class(x509.BasicConstraints)
    assert constraints.critical
    assert constraints.value.ca
    assert constraints.value.path_length == 0
    usage = ca.extensions.get_extension_for_class(x509.KeyUsage)
    assert usage.critical
    assert usage.value.key_cert_sign
    assert not usage.value.digital_signature
    assert ca.not_valid_before_utc == NOW - certificates.CLOCK_SKEW
    assert ca.not_valid_after_utc == NOW + certificates.CA_VALIDITY


def test_client_certificate(
    ca: x509.Certificate, ca_key: ec.EllipticCurvePrivateKey
) -> None:
    certificate = client(ca, ca_key)
    assert certificate.version is x509.Version.v3
    assert (
        certificate.signature_algorithm_oid == SignatureAlgorithmOID.ECDSA_WITH_SHA256
    )
    assert (
        certificate.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
        == "reaper:alice"
    )
    assert certificate.issuer == ca.subject
    assert certificates.issued_by(certificate, ca)
    constraints = certificate.extensions.get_extension_for_class(x509.BasicConstraints)
    assert constraints.critical
    assert not constraints.value.ca
    usage = certificate.extensions.get_extension_for_class(x509.KeyUsage)
    assert usage.critical
    assert usage.value.digital_signature
    assert not usage.value.key_cert_sign
    assert (
        ExtendedKeyUsageOID.CLIENT_AUTH
        in certificate.extensions.get_extension_for_class(x509.ExtendedKeyUsage).value
    )
    authority = certificate.extensions.get_extension_for_class(
        x509.AuthorityKeyIdentifier
    ).value
    assert authority.key_identifier.hex() == certificates.ski(ca)
    assert certificate.not_valid_before_utc == NOW - certificates.CLOCK_SKEW
    assert certificate.not_valid_after_utc == NOW + LIFETIME


def test_serial_numbers_differ(
    ca: x509.Certificate, ca_key: ec.EllipticCurvePrivateKey
) -> None:
    assert client(ca, ca_key).serial_number != client(ca, ca_key).serial_number


def test_refuses_another_keys_signature(ca: x509.Certificate) -> None:
    impostor = ec.generate_private_key(ec.SECP256R1())
    with pytest.raises(ValueError, match="does not verify against the CA"):
        client(ca, impostor)
    with pytest.raises(ValueError, match="does not verify against its own key"):
        certificates.ca_certificate(
            "reaper",
            ec.generate_private_key(ec.SECP256R1()).public_key(),
            signer(impostor),
            NOW,
        )


def test_another_ca_did_not_issue(
    ca: x509.Certificate, ca_key: ec.EllipticCurvePrivateKey
) -> None:
    other_key = ec.generate_private_key(ec.SECP256R1())
    other = certificates.ca_certificate(
        "reaper", other_key.public_key(), signer(other_key), NOW
    )
    assert not certificates.issued_by(client(ca, ca_key), other)


def test_refuses_to_outlive_the_ca(
    ca: x509.Certificate, ca_key: ec.EllipticCurvePrivateKey
) -> None:
    with pytest.raises(ValueError, match="expires before"):
        client(ca, ca_key, now=NOW + certificates.CA_VALIDITY)

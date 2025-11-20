#!/bin/bash
# update-adguard-credentials.sh

echo "Updating AdGuardHome credentials..."
echo ""

# Get new username
read -p "Enter new AdGuardHome username (default: admin): " NEW_USERNAME
if [ -z "$NEW_USERNAME" ]; then
    NEW_USERNAME="admin"
fi

# Get new password with confirmation
while true; do
    read -sp "Enter new AdGuardHome password: " NEW_PASSWORD
    echo ""
    read -sp "Confirm new AdGuardHome password: " NEW_PASSWORD_CONFIRM
    echo ""
    
    if [ "$NEW_PASSWORD" = "$NEW_PASSWORD_CONFIRM" ]; then
        if [ -z "$NEW_PASSWORD" ]; then
            echo "    ✗ Password cannot be empty. Please try again."
            echo ""
        else
            echo "    ✓ Passwords match"
            break
        fi
    else
        echo "    ✗ Passwords do not match. Please try again."
        echo ""
    fi
done

# Generate password hash
if ! command -v htpasswd &> /dev/null; then
    NEW_PASSWORD_HASH=$(docker run --rm httpd:alpine htpasswd -nbB "${NEW_USERNAME}" "${NEW_PASSWORD}" | cut -d ":" -f 2)
else
    NEW_PASSWORD_HASH=$(htpasswd -nbB "${NEW_USERNAME}" "${NEW_PASSWORD}" | cut -d ":" -f 2)
fi

# Update the secret
echo "Updating secret..."
kubectl delete secret adguardhome-password -n adguardhome 2>/dev/null || true
kubectl create secret generic adguardhome-password \
    --from-literal=password-hash="${NEW_PASSWORD_HASH}" \
    --from-literal=username="${NEW_USERNAME}" \
    -n adguardhome

# Restart AdGuardHome to use new credentials
echo "Restarting AdGuardHome..."
kubectl delete pod -n adguardhome -l app=adguardhome

echo "✓ AdGuardHome credentials updated successfully!"
echo "New username: ${NEW_USERNAME}"
echo "AdGuardHome will be available at https://adguard.yourdomain.local"

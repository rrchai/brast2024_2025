import requests
from io import StringIO
import synapseclient
import logging


def fetch_google_sheet_data(csv_url):
    """Fetch data from Google Sheets exported as CSV."""
    try:
        logger.info("Fetching Google Sheet data...")
        response = requests.get(csv_url)
        response.raise_for_status()
        csv_data = StringIO(response.text)
        reader = csv.DictReader(csv_data)
        rows = list(reader)
        logger.info(f"Fetched {len(rows)} rows from the Google Sheet.")
        return rows
    except Exception as e:
        logger.error(f"Error fetching Google Sheet data: {e}")
        return []


def get_unique_rows(rows):
    """Ensure rows are unique by Synapse Username."""
    unique_rows = {}
    for row in rows:
        # Use Synapse Username as the unique key
        key = row.get("Synapse Username")
        if key and key not in unique_rows:
            unique_rows[key] = row
    logger.info(
        f"Filtered to {len(unique_rows)} unique rows by Synapse Username.")
    return list(unique_rows.values())


def get_challenge_id(entity_id):
    """Retrieve the challenge ID associated with the entity."""
    try:
        challenge = syn.restGET(f"/entity/{entity_id}/challenge")
        challenge_id = challenge.get("id")
        logger.info(f"Challenge ID retrieved: {challenge_id}")
        return challenge_id
    except Exception as e:
        logger.error(
            f"Error retrieving challenge ID for entity {entity_id}: {e}")
        return None


def get_team_members(team_id):
    """Retrieve all members of a Synapse team."""
    try:
        members = syn.getTeamMembers(team_id)
        team_members = [member["member"]["userName"] for member in members]
        return team_members
    except Exception as e:
        logger.error(f"Error retrieving members for team {team_id}: {e}")
        return []


def get_registered_teams(challenge_id):
    """
    Retrieve all teams registered for the challenge in one call using the maximum limit.

    Args:
        challenge_id (str): Synapse challenge ID.

    Returns:
        list: List of all registered team IDs.
    """
    try:
        # Fetch all results in one API call by setting the maximum limit
        endpoint = f"/challenge/{challenge_id}/challengeTeam?limit=1000"
        response = syn.restGET(endpoint)

        # Extract team IDs from the response
        registered_teams = [team["teamId"]
                            for team in response.get("results", [])]
        logger.info(f"Retrieved {len(registered_teams)} registered teams.")
        return registered_teams
    except Exception as e:
        logger.error(
            f"Error retrieving registered teams for challenge {challenge_id}: {e}")
        return []


def get_all_registered_team_members(challenge_id):
    """Retrieve all members of all registered teams for a challenge."""
    team_members = set()
    team_ids = get_registered_teams(challenge_id)
    for team_id in team_ids:
        members = get_team_members(team_id)
        team_members.update(members)
    logger.info(
        f"Total registered team members retrieved: {len(team_members)}")
    return team_members


def validate_synapse_user(user):
    """Validate if a Synapse user exists using getUserProfile."""
    if not user:
        return None
    try:
        user = syn.getUserProfile(user)
        return user["ownerId"]
    except synapseclient.core.exceptions.SynapseHTTPError:
        return None
    except ValueError as e:
        return None


def is_user_registered(user_id, team_members):
    """Check if a user is either in the registration team or in any registered team."""
    if not user_id:
        return False
    # Check direct registration team
    if is_user_in_team(REGISTRATION_TEAM_ID, user_id):
        return True
    # Check registered team members
    if user_id in team_members:
        return True
    return False


def is_user_in_team(team_id, user_id):
    """Check if the given user is already in the Synapse team."""
    try:
        members = syn.getTeamMembers(team_id)
        for member in members:
            if member["member"]["ownerId"] == user_id:
                return True
        return False
    except Exception as e:
        logger.error(f"Error checking team membership for {user_id}: {e}")
        return False


def has_pending_invitation(team_id, user_id):
    """Check if the user has a pending invitation to the Synapse team."""
    try:
        invitations = syn.get_team_open_invitations(team_id)
        for invitation in invitations:
            if invitation["inviteeId"] == user_id:
                return True
        return False
    except Exception as e:
        logger.error(f"Error checking pending invitations for {user_id}: {e}")
        return False


def validate_responses(rows, registered_team_members):
    """Validate responses based on Synapse user checks, team membership, and invitations."""
    valid_responses = []
    for row in rows:
        synapse_username = row.get("Synapse Username")

        # Validate Synapse username
        user_id = validate_synapse_user(synapse_username)
        if not user_id:
            logger.warning(f"Invalid Synapse Username: {synapse_username}")
            # row["submitterid"] = user_id
            # row["Validation Status"] = "FAILED"
            # row["Validation Error"] = "Invalid Username"
            continue  # Skip invalid usernames

        # Check registration status
        if not is_user_registered(user_id, registered_team_members):
            logger.warning(f"User not registered: {user_id}")
            # row["submitterid"] = user_id
            # row["StaValidation Statustus"] = "FAILED"
            # row["Validation Error"] = "Not Registered"
            continue  # Skip unregistered users

        # Check if already in data access team
        if is_user_in_team(DATA_ACCESS_TEAM_ID, user_id):
            logger.info(
                f"{user_id} is already in the data access team.")
            # row["submitterid"] = user_id
            # row["Validation Status"] = "JOINED"
            # row["Validation Error"] = "Already in the data access team"
            continue  # Skip users already in the team

        # Check if a pending invitation exists
        if has_pending_invitation(DATA_ACCESS_TEAM_ID, user_id):
            logger.info(f"{user_id} has a pending invitation.")
            # row["submitterid"] = user_id
            # row["Validation Status"] = "FAILED"
            # row["Validation Error"] = "Pending invitation"
            continue  # Skip users with pending invitations

        # Add valid response
        row["submitterid"] = user_id
        # row["Validation Status"] = "RECEIVED"
        # row["Validation Error"] = ""
        valid_responses.append(row)

    logger.info(
        f"{len(valid_responses)} valid responses out of {len(rows)} total.")
    return valid_responses


def invite_user_to_team(team_id, user_id):
    """Invite a Synapse user to a team"""
    try:
        invitation_message = (
            "Thank you for your interest in the BraTS 2024 Challenge! <br/><br/>"
            "Once you click 'Join', you will be able to access the challenge data."
        )
        # Send the invitation
        syn.invite_to_team(
            team=team_id,
            user=user_id,
            message=invitation_message,
        )
        logger.info(f"Invitation sent to user {user_id} for team {team_id}.")
    except Exception as e:
        logger.error(f"Error inviting user {user_id} to team {team_id}: {e}")


def send_email_to_admin(admin_id, validated_responses):
    """Send an email to the admin with a summary of processed responses."""
    try:
        # Email subject
        subject = "BraTS 2024 Data Access Team Invitation Update"

        # Prepare HTML message body
        message_body = (
            "<p>Dear BraTS 2024 Admin,</p>"
            "<p>This is an automated notification to inform you that the following responses have been invited to join the "
            "<a href='https://www.synapse.org/#!Team:3502558' target='_blank'>BraTS 2024 Data Access Team</a>:</p>"
            "<table border='1' cellpadding='5' cellspacing='0' style='border-collapse: collapse;'>"
            "<thead>"
            "<tr>"
            "<th style='border: 1px solid black; padding: 5px;'>Timestamp</th>"
            "<th style='border: 1px solid black; padding: 5px;'>Username</th>"
            "<th style='border: 1px solid black; padding: 5px;'>User ID</th>"
            "<th style='border: 1px solid black; padding: 5px;'>Team</th>"
            "</tr>"
            "</thead>"
            "<tbody>"
        )
        for response in validated_responses:
            timestamp = response.get("Timestamp", "N/A")
            username = response.get("Synapse Username", "N/A")
            user_id = response.get("submitterid", "N/A")
            team = response.get("Synapse Challenge Team", "N/A")
            message_body += (
                f"<tr>"
                f"<td>{timestamp}</td>"
                f"<td>{username}</td>"
                f"<td>{user_id}</td>"
                f"<td>{team}</td>"
                f"</tr>"
            )
        message_body += (
            "</tbody>"
            "</table>"
            "<p>Best regards,<br/>The BraTS 2024 Automation</p>"
        )

        # Send the email
        syn.sendMessage(
            userIds=[admin_id],
            messageSubject=subject,
            messageBody=message_body,
            contentType="text/html",  # Enable HTML content
        )
        logger.info("Email sent to admin successfully.")
    except Exception as e:
        logger.error(f"Error sending email to admin: {e}")


if __name__ == "__main__":

    # Initialize logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    # Synapse setup
    syn = synapseclient.Synapse()
    syn.login()

    # Synapse registration team ID
    REGISTRATION_TEAM_ID = "3501723"
    DATA_ACCESS_TEAM_ID = "3502558"

    # Google Sheet CSV URL
    # SHEET_CSV_URL = "https://docs.google.com/spreadsheets/d/1yVT4SFslQ64wA61IuTgWCRdzhqhG-IygZnuYygc-Y4s/export?format=csv"
    SHEET_CSV_URL = "https://docs.google.com/spreadsheets/d/18Z7DZqGFeiEW_S9zC-Z9Ovfqdnk34vpfi5m2JgjVNUE/export?format=csv"
    # Entity ID for the challenge
    ENTITY_ID = "syn53708249"

    # Fetch data from the Google Sheet
    responses = fetch_google_sheet_data(SHEET_CSV_URL)

    # Ensure unique rows by Synapse Username
    unique_responses = get_unique_rows(responses)

    # Retrieve challenge ID and registered team members
    challenge_id = get_challenge_id(ENTITY_ID)
    registered_team_members = get_all_registered_team_members(challenge_id)

    valid_responses = validate_responses(
        unique_responses, registered_team_members)

    if valid_responses:
        # Send invitations for valid responses
        for response in valid_responses:
            user_id = response.get("submitterid")
            if user_id:
                invite_user_to_team(DATA_ACCESS_TEAM_ID, user_id)

        admin_id = syn.getUserProfile()["ownerId"]
        send_email_to_admin(admin_id, valid_responses)
    else:
        logger.info(
            "No valid responses found. Skipping invitations and email notifications.")

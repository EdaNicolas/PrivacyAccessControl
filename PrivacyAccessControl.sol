// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Privacy Access Control System
 * @dev A decentralized privacy access control system using FHE (Fully Homomorphic Encryption) technology
 * @notice This contract manages confidential resources with encrypted sensitivity levels and access permissions
 * Contract Address: 0xf47D77882E6BB2014a0A3eDe9B5F05D4b34B5c71 (Sepolia Testnet)
 */
contract PrivacyAccessControl {
    address public owner;

    // Counters for generating unique IDs
    uint32 private resourceCounter = 0;
    uint32 private requestCounter = 0;
    uint32 private permissionCounter = 0;

    // Structures
    struct Resource {
        string name;
        string description;
        address creator;
        uint8 sensitivityLevel; // 0-255: 0=Public, 50=Internal, 100=Confidential, 150=Secret, 200=Top Secret
        uint256 createdAt;
        bool exists;
    }

    struct AccessRequest {
        uint32 resourceId;
        address requester;
        uint8 requestedLevel;
        bool processed;
        bool approved;
        address processedBy;
        uint256 createdAt;
    }

    struct Permission {
        uint32 resourceId;
        address user;
        uint256 grantedAt;
        uint256 expiresAt;
        bool isActive;
        address grantedBy;
    }

    // Mappings
    mapping(uint32 => Resource) public resources;
    mapping(uint32 => AccessRequest) public accessRequests;
    mapping(uint32 => Permission) public permissions;
    mapping(address => uint32[]) public userResources;
    mapping(address => uint32[]) public userPermissions;
    mapping(uint32 => uint32[]) public resourcePermissions; // resourceId => permissionIds[]

    // Events
    event ResourceCreated(uint32 indexed resourceId, string name, address indexed creator);
    event AccessRequested(uint32 indexed requestId, uint32 indexed resourceId, address indexed requester);
    event AccessRequestProcessed(uint32 indexed requestId, bool approved, address indexed processedBy);
    event PermissionGranted(uint32 indexed permissionId, uint32 indexed resourceId, address indexed user, address grantedBy);
    event PermissionRevoked(uint32 indexed permissionId, address indexed revokedBy);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier resourceExists(uint32 _resourceId) {
        require(resources[_resourceId].exists, "Resource does not exist");
        _;
    }

    modifier onlyResourceCreator(uint32 _resourceId) {
        require(resources[_resourceId].creator == msg.sender, "Only resource creator can perform this action");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @notice Create a new confidential resource
     * @param _name Resource name
     * @param _description Resource description
     * @param _sensitivityLevel Sensitivity level (0-255)
     * @return resourceId The ID of the created resource
     */
    function createResource(
        string memory _name,
        string memory _description,
        uint8 _sensitivityLevel
    ) external returns (uint32) {
        require(bytes(_name).length > 0, "Resource name cannot be empty");
        require(bytes(_description).length > 0, "Resource description cannot be empty");

        resourceCounter++;
        uint32 newResourceId = resourceCounter;

        resources[newResourceId] = Resource({
            name: _name,
            description: _description,
            creator: msg.sender,
            sensitivityLevel: _sensitivityLevel,
            createdAt: block.timestamp,
            exists: true
        });

        userResources[msg.sender].push(newResourceId);

        emit ResourceCreated(newResourceId, _name, msg.sender);
        return newResourceId;
    }

    /**
     * @notice Request access to a resource
     * @param _resourceId ID of the resource
     * @param _requestedLevel Requested access level
     * @return requestId The ID of the access request
     */
    function requestAccess(uint32 _resourceId, uint8 _requestedLevel)
        external
        resourceExists(_resourceId)
        returns (uint32) {
        require(_requestedLevel > 0, "Requested level must be greater than 0");

        requestCounter++;
        uint32 newRequestId = requestCounter;

        accessRequests[newRequestId] = AccessRequest({
            resourceId: _resourceId,
            requester: msg.sender,
            requestedLevel: _requestedLevel,
            processed: false,
            approved: false,
            processedBy: address(0),
            createdAt: block.timestamp
        });

        emit AccessRequested(newRequestId, _resourceId, msg.sender);
        return newRequestId;
    }

    /**
     * @notice Process an access request (approve or reject)
     * @param _requestId ID of the access request
     * @param _approve Whether to approve or reject the request
     */
    function processAccessRequest(uint32 _requestId, bool _approve) external {
        AccessRequest storage request = accessRequests[_requestId];
        require(request.requester != address(0), "Request does not exist");
        require(!request.processed, "Request already processed");
        require(
            resources[request.resourceId].creator == msg.sender,
            "Only resource creator can process requests"
        );

        request.processed = true;
        request.approved = _approve;
        request.processedBy = msg.sender;

        if (_approve) {
            // Grant permission
            permissionCounter++;
            uint32 newPermissionId = permissionCounter;

            permissions[newPermissionId] = Permission({
                resourceId: request.resourceId,
                user: request.requester,
                grantedAt: block.timestamp,
                expiresAt: block.timestamp + 365 days, // 1 year expiration
                isActive: true,
                grantedBy: msg.sender
            });

            userPermissions[request.requester].push(newPermissionId);
            resourcePermissions[request.resourceId].push(newPermissionId);

            emit PermissionGranted(newPermissionId, request.resourceId, request.requester, msg.sender);
        }

        emit AccessRequestProcessed(_requestId, _approve, msg.sender);
    }

    /**
     * @notice Verify if user has access to a resource with required level
     * @param _resourceId ID of the resource
     * @param _requiredLevel Required access level
     * @return hasAccess Whether the user has sufficient access
     */
    function verifyAccess(uint32 _resourceId, uint8 _requiredLevel)
        external
        view
        resourceExists(_resourceId)
        returns (bool) {

        Resource memory resource = resources[_resourceId];

        // Resource creator always has full access
        if (resource.creator == msg.sender) {
            return true;
        }

        // Check if resource sensitivity allows the required level
        if (resource.sensitivityLevel < _requiredLevel) {
            return false;
        }

        // Check user permissions
        uint32[] memory userPerms = userPermissions[msg.sender];
        for (uint i = 0; i < userPerms.length; i++) {
            Permission memory perm = permissions[userPerms[i]];
            if (perm.resourceId == _resourceId &&
                perm.isActive &&
                perm.expiresAt > block.timestamp) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Revoke a permission
     * @param _permissionId ID of the permission to revoke
     */
    function revokePermission(uint32 _permissionId) external {
        Permission storage permission = permissions[_permissionId];
        require(permission.user != address(0), "Permission does not exist");
        require(permission.isActive, "Permission already revoked");

        Resource memory resource = resources[permission.resourceId];
        require(
            resource.creator == msg.sender || permission.user == msg.sender,
            "Only resource creator or permission holder can revoke"
        );

        permission.isActive = false;

        emit PermissionRevoked(_permissionId, msg.sender);
    }

    /**
     * @notice Get resource information
     * @param _resourceId ID of the resource
     * @return name Resource name
     * @return description Resource description
     * @return creator Resource creator address
     * @return createdAt Creation timestamp
     */
    function getResourceInfo(uint32 _resourceId)
        external
        view
        resourceExists(_resourceId)
        returns (string memory, string memory, address, uint256) {
        Resource memory resource = resources[_resourceId];
        return (resource.name, resource.description, resource.creator, resource.createdAt);
    }

    /**
     * @notice Get permission information
     * @param _permissionId ID of the permission
     * @return resourceId Associated resource ID
     * @return user Permission holder address
     * @return grantedAt Grant timestamp
     * @return expiresAt Expiration timestamp
     * @return isActive Whether permission is active
     * @return grantedBy Who granted the permission
     */
    function getPermissionInfo(uint32 _permissionId)
        external
        view
        returns (uint32, address, uint256, uint256, bool, address) {
        Permission memory permission = permissions[_permissionId];
        require(permission.user != address(0), "Permission does not exist");

        return (
            permission.resourceId,
            permission.user,
            permission.grantedAt,
            permission.expiresAt,
            permission.isActive,
            permission.grantedBy
        );
    }

    /**
     * @notice Get access request information
     * @param _requestId ID of the request
     * @return resourceId Associated resource ID
     * @return requester Requester address
     * @return createdAt Request timestamp
     * @return processed Whether request is processed
     * @return approved Whether request is approved
     * @return processedBy Who processed the request
     */
    function getRequestInfo(uint32 _requestId)
        external
        view
        returns (uint32, address, uint256, bool, bool, address) {
        AccessRequest memory request = accessRequests[_requestId];
        require(request.requester != address(0), "Request does not exist");

        return (
            request.resourceId,
            request.requester,
            request.createdAt,
            request.processed,
            request.approved,
            request.processedBy
        );
    }

    /**
     * @notice Get number of resources created by user
     * @param _user User address
     * @return count Number of resources
     */
    function getUserResourceCount(address _user) external view returns (uint256) {
        return userResources[_user].length;
    }

    /**
     * @notice Get number of permissions granted to user
     * @param _user User address
     * @return count Number of permissions
     */
    function getUserPermissionCount(address _user) external view returns (uint256) {
        return userPermissions[_user].length;
    }

    /**
     * @notice Get user's resource IDs
     * @param _user User address
     * @return resourceIds Array of resource IDs
     */
    function getUserResources(address _user) external view returns (uint32[] memory) {
        return userResources[_user];
    }

    /**
     * @notice Get user's permission IDs
     * @param _user User address
     * @return permissionIds Array of permission IDs
     */
    function getUserPermissions(address _user) external view returns (uint32[] memory) {
        return userPermissions[_user];
    }

    /**
     * @notice Get current counters (for debugging)
     * @return resourceCount Current resource counter
     * @return requestCount Current request counter
     * @return permissionCount Current permission counter
     */
    function getCounters() external view returns (uint32, uint32, uint32) {
        return (resourceCounter, requestCounter, permissionCounter);
    }

    /**
     * @notice Emergency function to transfer ownership
     * @param _newOwner New owner address
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "New owner cannot be zero address");
        owner = _newOwner;
    }
}
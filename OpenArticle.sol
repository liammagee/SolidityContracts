pragma solidity ^0.4.19;

import "./ERC20.sol";


contract OpenArticle {
/************************************************************/
/*********************** public data ************************/
/************************************************************/
    TokenERC20 public _ScienceToken;
    
    bytes32[] public versions; //metaData
    mapping(bytes32 => bytes32[]) public additionalData; //pdf's for example
    mapping(bytes32 => bytes32[]) public reviews;

    mapping(bytes32 => address[]) public madeBy;
    mapping(bytes32 => address) public acceptedBy; //if it's 0, it's not approved
    mapping(bytes32 => address) public retractedBy;
    mapping(bytes32 => address) public rejectedBy;
    mapping(bytes32 => address) public punishedBy;
    mapping(bytes32 => uint) public timestamp;
    mapping(bytes32 => uint) public claimed;

    address[] public authors;
    mapping(address => bool) isAdmin;

    bytes32[] public comments;
    
    uint public coAuthorBounty;
    uint public reviewBounty;
    uint public coAuthorClaim;
    uint public reviewClaim;
    
/************************************************************/

/************************************************************/
/************************* modifiers ************************/
/************************************************************/
    modifier mainAuthorAccess {
        require(isAdmin[msg.sender]);
        _;
    }
    
    function virginLink(bytes32 _ipfsLink) private view returns (bool) {
        return (     acceptedBy[_ipfsLink] == address(0) &&
                    retractedBy[_ipfsLink] == address(0) &&
                    rejectedBy[_ipfsLink] == address(0) &&
                    punishedBy[_ipfsLink] == address(0)
        );
    }
    
    modifier creatorAccess(bytes32 _ipfsLink) {
        bool isAuthor = false;
        uint i = 0;
        while ((i < madeBy[_ipfsLink].length) && (!isAuthor)){
            isAuthor = (madeBy[_ipfsLink][i] == msg.sender);
            i++;
        }
        require(isAuthor);
        _;
    }
/************************************************************/

/************************************************************/
/***************** contract creation ************************/
/************************************************************/
    function OpenArticle(address _scienceToken, bytes32 _initialVersion, address[] _coAuthors, bytes32[] _additionalData) public {
        //init Token
        _ScienceToken = TokenERC20(_scienceToken);
        //init authors
        authors.push(msg.sender);
        versions.push(_initialVersion);
        madeBy[_initialVersion].push(msg.sender);
        //init coauthors
        for(uint i = 0; i < _coAuthors.length; i++){
            authors.push(_coAuthors[i]);
            madeBy[_initialVersion].push(_coAuthors[i]);
        }
        //releaseVersion
        acceptedBy[_initialVersion] = msg.sender;
        timestamp[_initialVersion] = now;
        claimed[_initialVersion] = 0;
        //add aditional info
        for(i = 0; i < _additionalData.length; i++){
            additionalData[_initialVersion].push(_additionalData[i]);
        }
    }
/************************************************************/


/************************************************************/
/********* getters (for full arrays) ************************/
/************************************************************/
    function getVersions() public view returns (bytes32[]){
        return versions;
    }
    
    function getAdditionalData (bytes32 _version) public view returns (bytes32[]){
        return (additionalData[_version]);
    }
    
    function getReviews (bytes32 _version) public view returns (bytes32[]){
        return (reviews[_version]);
    }
    
    function getEntryData(bytes32 _ipfsLink) public view returns (address[], address, address, address, address, uint){
        return (madeBy[_ipfsLink], acceptedBy[_ipfsLink], retractedBy[_ipfsLink], rejectedBy[_ipfsLink], punishedBy[_ipfsLink], timestamp[_ipfsLink]);
    }
    
    function getAuthors() public view returns (address[]){
        return (authors);
    }
/************************************************************/

/************************************************************/
/********* setters (main author access) *********************/
/************************************************************/
    //only possible to add? safer. allow also non-authors (for editors)
    function changeAuthorStatus(address _newAuthor) public mainAuthorAccess {
        isAdmin[_newAuthor] = true;
    }
    
    //rewards and punishments
    function setBounties(uint _coAuthorBounty, uint _reviewBounty, uint _coAuthorClaim, uint _reviewClaim) public mainAuthorAccess {
        coAuthorBounty = _coAuthorBounty;
        reviewBounty = _reviewBounty;
        coAuthorClaim = _coAuthorClaim;
        reviewClaim = _reviewClaim;
    }
    
    /********* private ******************************************/
    function reject(bytes32 _ipfsLink, bool _punish, uint _claim) private {
        require(virginLink(_ipfsLink));
        rejectedBy[_ipfsLink] = msg.sender;
        timestamp[_ipfsLink] = now;
        if (_punish){
            punishedBy[_ipfsLink] = msg.sender;
        }
        else{
             _ScienceToken.transfer(madeBy[_ipfsLink][0], _claim); //let them split it themselves
        }
    }
    function accept(bytes32 _ipfsLink, uint _reward) private {
        require(virginLink(_ipfsLink));
        acceptedBy[_ipfsLink] = msg.sender;
        timestamp[_ipfsLink] = now;
        _ScienceToken.transfer(madeBy[_ipfsLink][0], _reward); //let them split it themselves
    }
    /************************************************************/
    
    function acceptVersion(bytes32 _version) public mainAuthorAccess {
        accept(_version, coAuthorBounty + claimed[_version]);
        for(uint i = 0; i < madeBy[_version].length; i++){
            authors.push(madeBy[_version][i]);
        }
    }
    
    function rejectVersion(bytes32 _version, bool _punish) public mainAuthorAccess{
        reject(_version, _punish, claimed[_version]);
    }
    
    function approveReview(bytes32 _review) public mainAuthorAccess {
        accept(_review, reviewBounty + claimed[_review]);
    }
    
    function rejectReview(bytes32 _review, bool _punish) public mainAuthorAccess{
        reject(_review, _punish, claimed[_review]);
    }
/************************************************************/

/************************************************************/
/************ changers (creator access) *********************/
/************************************************************/
    function retractVersion(bytes32 _version) public creatorAccess(_version) {
        retractedBy[_version] = msg.sender;
        if (virginLink(_version)) //cancel
        {
            _ScienceToken.transfer(madeBy[_version][0], claimed[_version]);
        }
    }

/************************************************************/
/****************** add new *********************************/
/************************************************************/
    //you'll have to transfer tokens first to attach the data
    function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public { 
        require(_token == address(_ScienceToken));
        require(_token == msg.sender);
        bytes32 ipfsLink;
        for (uint i = 0; i < 32; i++) {
            ipfsLink |= bytes32(_extraData[i] & 0xFF) >> (i * 8);
        }
        _ScienceToken.transferFrom(_from, this, _value);
        claimed[ipfsLink] = _value;
    }
    
    function addVersion(bytes32 _version, address[] _coAuthors, bytes32[] _additionalData) public {
        require (claimed[_version] >= coAuthorClaim); //check that claim is made
        versions.push(_version);
        madeBy[_version].push(msg.sender);
        for(uint i = 0; i < _coAuthors.length; i++){
            madeBy[_version].push(_coAuthors[i]);
        }
        for(i = 0; i < _additionalData.length; i++){
            additionalData[_version].push(_additionalData[i]);
        }
    }
    
    function addReview(bytes32 _version, bytes32 _review, address[] _coReviewers) public {
        require (claimed[_review] >= reviewClaim); //check that claim is made
        reviews[_version].push(_review);
        madeBy[_review].push(msg.sender);
        for(uint i = 0; i < _coReviewers.length; i++){
            madeBy[_review].push(_coReviewers[i]);
        }
    }
    
    function addComment(bytes32 _comment) public {
        comments.push(_comment);
    }

/************************************************************/

/************************************************************/
/******************** close *********************************/
/************************************************************/
    function closeArticle () mainAuthorAccess public {
        bool VirginCommits = false;
        uint i = 0;
        uint j = 0;
        while ((i < versions.length)&&(!VirginCommits)) //in theoretical case of huge number of rewiews/versions the article will be "unclosable". this is OK.
        {
            VirginCommits = virginLink(versions[i]);
            j = 0;
            while ((j < reviews[versions[i]].length)&&(!VirginCommits))
            {
                VirginCommits = virginLink(reviews[versions[i]][j]);
            }
            i++;
        }
        require(!VirginCommits);
        _ScienceToken.transfer(authors[0], _ScienceToken.balanceOf(this));  //this withdraws the pot and effectively closes the article untill someone pays to re-open it.
    }
}